"""Check the local OCR HTTP boundary without loading a model."""

import base64
import io
import unittest

from fastapi.testclient import TestClient
from PIL import Image

from server import create_app


class LocalOCRTests(unittest.TestCase):
    def test_image_stays_in_memory_and_text_is_returned_verbatim(self):
        seen = []

        async def recognize(image, prompt, max_tokens):
            seen.append((image.size, image.getpixel((0, 0)), prompt, max_tokens))
            return "hello\nworld"

        image = Image.new("RGB", (24, 12), (20, 30, 40))
        encoded = io.BytesIO()
        image.save(encoded, format="PNG")
        uri = "data:image/png;base64," + base64.b64encode(encoded.getvalue()).decode()
        client = TestClient(create_app(recognize, "test-model"))
        response = client.post("/v1/chat/completions", json={
            "model": "test-model",
            "max_completion_tokens": 100,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": "Read horizontally."},
                {"type": "image_url", "image_url": {"url": uri}},
            ]}],
        })
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["choices"][0]["message"]["content"], "hello\nworld")
        self.assertEqual(seen, [((24, 12), (20, 30, 40), "Read horizontally.", 100)])

    def test_remote_images_are_rejected_before_recognition(self):
        async def recognize(*args):
            self.fail("Recognition must not run for a remote image.")

        client = TestClient(create_app(recognize, "test-model"))
        response = client.post("/v1/chat/completions", json={
            "model": "test-model",
            "messages": [{"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": "https://example.com/image.png"}},
            ]}],
        })
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
