"""Local OpenAI-compatible OCR endpoint with no screenshot or prompt cache."""

import argparse
import asyncio
import base64
import binascii
import io
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from typing import Awaitable, Callable, Literal

from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import AliasChoices, BaseModel, Field

Recognizer = Callable[[Image.Image, str, int], Awaitable[str]]
MODEL_REVISIONS = {
    "PaddlePaddle/PaddleOCR-VL-1.6": "c5630abae1d940eafe0697512a0325494b02ab42",
    "mlx-community/GLM-OCR-bf16": "24f15402e83baa0a80eeeaecf5480e172abc6f2e",
}


class ImageURL(BaseModel):
    url: str


class ContentItem(BaseModel):
    type: Literal["text", "image_url"]
    text: str | None = None
    image_url: ImageURL | None = None


class Message(BaseModel):
    role: str
    content: str | list[ContentItem]


class ChatRequest(BaseModel):
    model: str
    messages: list[Message]
    stream: bool = False
    max_tokens: int | None = Field(default=2048, ge=1, le=4096,
                                  validation_alias=AliasChoices("max_completion_tokens", "max_tokens"))


def create_app(recognize: Recognizer, model_id: str) -> FastAPI:
    """Expose one loaded model; accept image bytes only, never files or URLs."""
    app = FastAPI()

    @app.get("/health")
    def health():
        return {"ready": True, "model": model_id}

    @app.post("/v1/chat/completions")
    async def ocr(request: ChatRequest):
        if request.model != model_id or request.stream:
            raise HTTPException(400, "Unsupported model or streaming request")
        text_parts, images = [], []
        for message in request.messages:
            if message.role != "user":
                continue
            if isinstance(message.content, str):
                text_parts.append(message.content)
                continue
            for item in message.content:
                if item.type == "text" and item.text:
                    text_parts.append(item.text)
                elif item.type == "image_url" and item.image_url:
                    images.append(item.image_url.url)
        if len(images) != 1:
            raise HTTPException(400, "Exactly one image is required")
        header, separator, encoded = images[0].partition(",")
        if separator != "," or header not in ("data:image/png;base64", "data:image/jpeg;base64"):
            raise HTTPException(400, "Only in-memory PNG or JPEG images are accepted")
        try:
            data = base64.b64decode(encoded, validate=True)
            with Image.open(io.BytesIO(data)) as source:
                image = source.convert("RGB")
        except (binascii.Error, ValueError, OSError):
            raise HTTPException(400, "Invalid image data") from None
        try:
            text = await recognize(image, "\n".join(text_parts), request.max_tokens or 2048)
        finally:
            image.close()
        return {
            "id": "local-ocr", "object": "chat.completion", "created": int(time.time()),
            "model": model_id,
            "choices": [{"index": 0, "message": {"role": "assistant", "content": text}, "finish_reason": "stop"}],
        }

    return app


def load_recognizer(model_id: str, detector: Path | None = None):
    """Load weights once and create a fresh generation cache for every image."""
    import mlx.core as mx
    from mlx_vlm import apply_chat_template, generate, load
    from mlx_vlm.utils import load_config
    from huggingface_hub import snapshot_download

    snapshot = snapshot_download(model_id, revision=MODEL_REVISIONS.get(model_id), local_files_only=True,
        allow_patterns=["*.json", "*.jsonl", "*.safetensors", "*.py", "*.model", "*.tiktoken", "*.txt", "*.jinja"])
    model, processor = load(snapshot)
    config = load_config(snapshot)

    def read_region(image: Image.Image, prompt: str, max_tokens: int) -> str:
        formatted = apply_chat_template(processor, config, prompt, num_images=1)
        try:
            result = generate(model, processor, formatted, image=image,
                              max_tokens=max_tokens, temperature=0.0, verbose=False)
            if result.generation_tokens >= max_tokens:
                raise RuntimeError("OCR output exceeded its token limit")
            return result.text
        finally:
            mx.clear_cache()

    def recognize(image: Image.Image, prompt: str, max_tokens: int) -> str:
        if detector is None:
            return read_region(image, prompt, max_tokens)
        from layout import detect_regions, recognize_horizontal

        def read(crop: Image.Image) -> str:
            with crop.resize((crop.width * 3, crop.height * 3), Image.Resampling.LANCZOS) as enlarged:
                return read_region(enlarged, prompt, max_tokens)

        return recognize_horizontal(image, detect_regions(image, detector), read)

    return recognize


if __name__ == "__main__":
    import uvicorn

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="PaddlePaddle/PaddleOCR-VL-1.6")
    parser.add_argument("--port", type=int, default=18871)
    parser.add_argument("--detector", type=Path, default=Path(__file__).resolve().parents[2] / ".local/detect-lines")
    args = parser.parse_args()
    # Keep model loading and generation on the same Metal worker thread.
    with ThreadPoolExecutor(max_workers=1) as worker:
        inference = worker.submit(load_recognizer, args.model, args.detector).result()

        async def recognize(image, prompt, max_tokens):
            return await asyncio.get_running_loop().run_in_executor(worker, inference, image, prompt, max_tokens)

        uvicorn.run(create_app(recognize, args.model), host="127.0.0.1", port=args.port, access_log=False)
