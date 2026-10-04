"""Compare local OCR models on a private image manifest; never copies images."""

import argparse
import json
import time
from pathlib import Path
from PIL import Image

from mlx_vlm import apply_chat_template, generate, load
from mlx_vlm.utils import load_config


def benchmark(model_id: str, manifest: Path, output: Path, task_prompt: str, detector: Path | None) -> None:
    """Save verbatim model output and timing for each supplied image."""
    started = time.perf_counter()
    if detector:
        from server import load_recognizer
        regional = load_recognizer(model_id, detector)
    else:
        model, processor = load(model_id)
        config = load_config(model_id)
    load_seconds = time.perf_counter() - started
    cases = json.loads(manifest.read_text())
    results = []
    for case in cases:
        case_prompt = case.get("prompt", task_prompt)
        prompt = case_prompt if detector else apply_chat_template(
            processor, config, case_prompt, num_images=1
        )
        started = time.perf_counter()
        with Image.open(case["image"]) as source:
            prepared = source.crop(case["crop"]) if "crop" in case else source.copy()
        if scale := case.get("scale"):
            resized = prepared.resize((prepared.width * scale, prepared.height * scale), Image.Resampling.LANCZOS)
            prepared.close()
            prepared = resized
        try:
            if detector:
                text = regional(prepared, prompt, 2048)
                result = None
            else:
                result = generate(
                    model, processor, prompt, image=prepared,
                    max_tokens=2048, temperature=0.0, verbose=False,
                )
                text = result.text
        finally:
            prepared.close()
        entry = {
            "case": case["name"], "model": model_id,
            "seconds": time.perf_counter() - started,
            "text": text,
            "generation_tokens": result.generation_tokens if result else None,
            "finish_reason": result.finish_reason if result else None,
        }
        if "expected" in case:
            entry["exact_match"] = text.strip() == case["expected"]
        results.append(entry)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps({"load_seconds": load_seconds, "results": results}, ensure_ascii=False, indent=2))
        print(json.dumps({k: v for k, v in entry.items() if k != "text"}), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model")
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--prompt")
    parser.add_argument("--detector", type=Path)
    args = parser.parse_args()
    default_prompts = {"PaddlePaddle/PaddleOCR-VL-1.6": "OCR:"}
    benchmark(args.model, args.manifest, args.output, args.prompt or default_prompts.get(args.model, "Text Recognition:"), args.detector)
