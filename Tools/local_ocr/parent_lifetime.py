"""Release the in-memory OCR model if its owning app disappears."""

import os
import threading
import time


def watch_parent(parent_pid: int) -> None:
    """Monitor the direct parent, including force quits that bypass app cleanup."""
    if parent_pid <= 1 or os.getppid() != parent_pid:
        raise ValueError("The OCR server must be launched by its owning app")

    def monitor():
        while True:
            time.sleep(0.25)
            if os.getppid() != parent_pid:
                # Inference may be busy; there is no request data to save on disk.
                os._exit(0)

    threading.Thread(target=monitor, name="app-lifetime", daemon=True).start()
