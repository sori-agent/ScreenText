"""Check the cloud launcher keeps credentials out of command arguments."""

import unittest
from pathlib import Path
from unittest.mock import patch

import openrouter_ocr


class OpenRouterLauncherTests(unittest.TestCase):
    def test_launch_uses_workspace_helper_and_keeps_key_in_environment(self):
        root = Path("/tmp/screentext-launch-test")
        with patch("openrouter_ocr.subprocess.run") as run:
            openrouter_ocr.launch_application(root, "private-test-key")
        arguments = run.call_args.args[0]
        self.assertEqual(arguments[:2], ["/usr/bin/swift", str(root / "Tools/local_ocr/LaunchApp.swift")])
        self.assertTrue(arguments[2].endswith("ScreenText.app"))
        self.assertNotIn("private-test-key", " ".join(arguments))
        self.assertEqual(run.call_args.kwargs["env"]["OPENROUTER_API_KEY"], "private-test-key")


if __name__ == "__main__":
    unittest.main()
