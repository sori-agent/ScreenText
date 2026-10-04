"""Prove that an abruptly terminated app cannot leave its OCR child running."""

import json
import select
import subprocess
import sys
import unittest


class ParentLifetimeTests(unittest.TestCase):
    def test_child_exits_when_its_parent_is_force_quit(self):
        child_code = """
import os, time
from parent_lifetime import watch_parent
watch_parent(os.getppid())
print('ready', flush=True)
time.sleep(300)
"""
        parent_code = """
import json, subprocess, sys
child = subprocess.Popen([sys.executable, '-c', json.loads(sys.argv[1])])
sys.stdin.readline()
"""
        parent = subprocess.Popen(
            [sys.executable, "-c", parent_code, json.dumps(child_code)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            ready, _, _ = select.select([parent.stdout], [], [], 5)
            self.assertTrue(ready, "The model child must announce startup.")
            self.assertEqual(parent.stdout.readline().strip(), "ready")
            self.assertIsNone(parent.poll(), "The model must stay alive while its app is running.")
            parent.kill()
            parent.wait(timeout=5)
            # The child inherits stdout; communicate returns only after that child also exits.
            output, errors = parent.communicate(timeout=5)
            self.assertEqual(errors, "")
            self.assertEqual(output, "")
        finally:
            if parent.poll() is None:
                parent.kill()
            parent.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
