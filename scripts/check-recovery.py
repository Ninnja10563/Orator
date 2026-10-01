"""Kill an actual editing process and verify recovery in a fresh process."""
import os
import pathlib
import subprocess
import tempfile
import time

app = pathlib.Path("build/Orator.app/Contents/MacOS/Orator").resolve()
with tempfile.TemporaryDirectory(prefix="orator-recovery-") as directory:
    env = dict(os.environ, ORATOR_RECOVERY_DIRECTORY=directory)
    process = subprocess.Popen([str(app), "--recovery-write-test"], env=env)
    try:
        deadline = time.monotonic() + 30
        while not (pathlib.Path(directory) / "ready").exists():
            if process.poll() is not None:
                raise RuntimeError("Editor exited before recovery was durable")
            if time.monotonic() > deadline:
                raise TimeoutError("Timed out waiting for a recovery snapshot")
            time.sleep(0.1)
        process.kill()  # SIGKILL: bypass document closing and cleanup.
        process.wait(timeout=10)
        subprocess.run([str(app), "--recovery-read-test"], env=env, check=True, timeout=30)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=10)
