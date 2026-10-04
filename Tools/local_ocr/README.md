# Local OCR trial

ScreenText is a personal macOS fork of [TRex](https://github.com/amebalabs/TRex). It keeps TRex's region selector and clipboard flow and runs [PaddleOCR-VL-1.6](https://github.com/PaddlePaddle/PaddleOCR) through [MLX-VLM](https://github.com/Blaizzy/mlx-vlm) on Apple Silicon. There is no API account or inference charge.

## Run

Requires Apple Silicon, Xcode, and [uv](https://docs.astral.sh/uv/getting-started/installation/).

```sh
Tools/local_ocr/setup.sh
Tools/local_ocr/start.sh
```

Setup downloads approximately 2 GB of model weights and builds the app. It uses this Mac's sole Apple Development certificate when available, or ad-hoc signing otherwise. Set `SCREENTEXT_SIGNING_IDENTITY` to select a specific certificate. After setup, inference runs offline. On this checkout you can double-click `Start ScreenText.command` to start it again.

Allow **ScreenText** in macOS **System Settings → Privacy & Security → Screen & System Audio Recording**. Press **⌘⇧2**, click to anchor one corner, drag to the opposite corner, and release to copy the region's text. Then paste. Escape cancels. The launcher skips the upstream introduction; some settings still use the TRex name. ScreenText has its own app identity and preferences.

Rebuilding an ad-hoc signed app can leave a stale Screen Recording entry that looks enabled. To replace that entry, run `tccutil reset ScreenCapture com.sori.ScreenText`, start the app, and grant ScreenText access again. This resets only ScreenText's screen permission. A stable Apple Development signature keeps the app identity consistent across rebuilds.

The launcher selects the local endpoint at `127.0.0.1:18871`, disables capture history and model post-processing, preserves line breaks, and uses macOS's native region picker. The GUI uses a normal preferences suite so the launcher can configure the local build without an Apple developer app group.

Successful GUI captures play macOS's Glass ding after the text has been written to the system clipboard. The existing **Play Sounds** setting controls both the capture sound and this ready sound. Cancelled captures and failed clipboard writes do not play the ready sound.

```sh
Tools/local_ocr/stop.sh
```

ScreenText starts the model as its own child process when the app opens. Choose **Quit ScreenText** to stop both the app and model and release their RAM. A force quit or crash also stops the model. Keeping the app in the menu bar keeps the model loaded; opening it again reloads the model, and an early capture waits for startup. No login service is installed. Starting the launcher again restarts this checkout's GUI to apply its configuration. `stop.sh` remains an emergency way to stop just the server.

## Output and limits

Apple Vision locates text boxes. Its transcription is used only to estimate script boundaries; the copied text comes from the local model. Horizontal boxes are read in row order. Small annotation boxes stay above their main line. Tall vertical boxes are excluded, though orientation and small annotations remain heuristic. Plain-text spaces approximate indentation; tables are not reconstructed in this trial.

The supplied subtitle sample matched exactly in local runs. The dense photographed textbook still has errors in mixed Japanese/Korean rows, punctuation, and furigana. This is a trial, with no guarantee of perfect transcription. GLM-OCR was also evaluated locally and performed worse on these Korean samples.

An unavailable server or exhausted token limit leaves the clipboard unchanged. Recognized text can still be wrong without triggering either condition. No calibrated confidence score is available.

The local server accepts PNG/JPEG bytes, never fetches image URLs, binds only to loopback, and keeps request images in memory. The native picker creates a temporary screenshot; the GUI loads it and immediately deletes that file before OCR starts. Capture history is disabled. Upstream history and remote-provider controls still exist; enabling them changes those guarantees. The upstream CLI is outside this trial.

## Focused checks

```sh
(cd Tools/local_ocr && ../../.venv/bin/python -m unittest test_server test_layout test_parent_lifetime)
(cd Packages/TRexLLM && swift test --jobs 2 --filter UnifiedLanguageModelProviderTests)
(cd Packages/TRexCore && swift test --jobs 2 --filter LocalOCRFailureTests)
(cd Packages/TRexCore && swift test --jobs 1 --filter LocalOCRServerTests)
```

`LocalOCRIntegrationTests` runs the configured model through the clipboard pipeline when `SCREENTEXT_TEST_IMAGE` and `SCREENTEXT_TEST_EXPECTED` point to private local files. It skips otherwise. The test replaces the clipboard with the recognized text.

`benchmark.py` accepts a private JSON manifest with `name`, absolute `image` path, optional `crop`, `scale`, and `expected` text. Put manifests and results under ignored `.local/`; never commit user screenshots or extracted textbook content. Pass `--detector .local/detect-lines` to use the same region pipeline as the server.

TRex and MLX-VLM are MIT licensed; PaddleOCR-VL-1.6 is Apache 2.0 licensed. Original upstream license files remain in this fork.

## Temporary OpenRouter trial

Double-click `Start Qwen.command` to select `qwen/qwen3.7-flash` at `https://openrouter.ai/api/v1`. This profile disables reasoning, limits provider prices to $0.03 per million input tokens and $0.13 per million output tokens, and has no fallback to another model. The local model is stopped and is not loaded in a cloud profile.

The launcher reads `OPENROUTER_API_KEY` from its environment, the key already entered in the app, or the current gcloud project's sole secret whose name contains `openrouter`, in that order. Set `SCREENTEXT_OPENROUTER_SECRET` to choose a secret when there is more than one. It preserves the user's configured key and never writes a retrieved key to preferences or files. Use the launcher again after quitting the app so it reloads the key. Double-click `Start ScreenText.command` to return to local OCR.

Cloud profiles open the app through `NSWorkspace` so macOS uses ScreenText's screen permission. The key is passed in the app's environment, never in command arguments. Running the app binary directly can incorrectly attribute its screenshots to the calling terminal or agent.

Screenshots are sent to OpenRouter's cloud provider. The prompt requests literal horizontal English/Japanese/Korean transcription, including furigana above its main line. An unavailable model leaves the clipboard unchanged. `Start Space Bunny.command` remains a separate temporary free profile; that model requires reasoning and OpenRouter lists it as going away October 5, 2026.
