# Local OCR trial

ScreenText is a personal macOS fork of [TRex](https://github.com/amebalabs/TRex). It keeps TRex's region selector and clipboard flow and runs [PaddleOCR-VL-1.6](https://github.com/PaddlePaddle/PaddleOCR) through [MLX-VLM](https://github.com/Blaizzy/mlx-vlm) on Apple Silicon. There is no API account or inference charge.

## Run

Requires Apple Silicon, Xcode, and [uv](https://docs.astral.sh/uv/getting-started/installation/).

```sh
Tools/local_ocr/setup.sh
Tools/local_ocr/start.sh
```

Setup downloads approximately 2 GB of model weights and builds an ad-hoc signed app. After setup, inference runs offline. On this checkout you can double-click `Start ScreenText.command` to start it again.

Allow **ScreenText** in macOS **System Settings → Privacy & Security → Screen & System Audio Recording**. Press **⌘⇧2**, move or resize the selection rectangle, click **Copy Text** (or press Return), then paste. Escape cancels. The launcher skips the upstream introduction; some settings still use the TRex name. ScreenText has its own app identity and preferences.

Rebuilding an ad-hoc signed app can invalidate its Screen Recording permission. If capture stops after a rebuild, switch ScreenText off and back on in that settings page, then choose Quit & Reopen if prompted.

The launcher selects the local endpoint at `127.0.0.1:18871`, disables capture history, disables model post-processing, preserves line breaks, and enables frozen selection. The GUI uses a normal preferences suite so the launcher can configure the ad-hoc build without an Apple developer app group.

```sh
Tools/local_ocr/stop.sh
```

Quit the menu bar app separately. The server is started by the launcher; no login service is installed. Starting again restarts this checkout's GUI to apply the launcher's configuration.

## Output and limits

Apple Vision locates text boxes. Its transcription is used only to estimate script boundaries; the copied text comes from the local model. Horizontal boxes are read in row order. Small annotation boxes stay above their main line. Tall vertical boxes are excluded, though orientation and small annotations remain heuristic. Plain-text spaces approximate indentation; tables are not reconstructed in this trial.

The supplied subtitle sample matched exactly in local runs. The dense photographed textbook still has errors in mixed Japanese/Korean rows, punctuation, and furigana. This is a trial, with no guarantee of perfect transcription. GLM-OCR was also evaluated locally and performed worse on these Korean samples.

An unavailable server or exhausted token limit leaves the clipboard unchanged. Recognized text can still be wrong without triggering either condition. No calibrated confidence score is available.

The local server accepts PNG/JPEG bytes, never fetches image URLs, binds only to loopback, and keeps request images in memory. With the launcher's frozen selection and history-disabled settings, GUI captures are not saved as screenshot files. Upstream history and remote-provider controls still exist; enabling them changes those guarantees. The upstream CLI is outside this trial.

## Focused checks

```sh
(cd Tools/local_ocr && ../../.venv/bin/python -m unittest test_server test_layout)
(cd Packages/TRexLLM && swift test --jobs 2 --filter UnifiedLanguageModelProviderTests)
(cd Packages/TRexCore && swift test --jobs 2 --filter LocalOCRFailureTests)
```

`LocalOCRIntegrationTests` runs the configured model through the clipboard pipeline when `SCREENTEXT_TEST_IMAGE` and `SCREENTEXT_TEST_EXPECTED` point to private local files. It skips otherwise. The test replaces the clipboard with the recognized text.

`benchmark.py` accepts a private JSON manifest with `name`, absolute `image` path, optional `crop`, `scale`, and `expected` text. Put manifests and results under ignored `.local/`; never commit user screenshots or extracted textbook content. Pass `--detector .local/detect-lines` to use the same region pipeline as the server.

TRex and MLX-VLM are MIT licensed; PaddleOCR-VL-1.6 is Apache 2.0 licensed. Original upstream license files remain in this fork.
