#!/usr/bin/env python3
"""Run a Godot check, drain diagnostics, and stop its owned process tree on failure."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ERROR_MARKER = b"ERROR:"
PORTABLE_PROCESS_WRAPPER = True


def stop_process(process):
    if process.poll() is not None:
        return
    if os.name == 'nt':
        # The Godot console launcher starts the engine as a child. Terminating
        # only the launcher leaves that engine running and the log file locked.
        killer = Path(os.environ['SystemRoot']) / 'System32' / 'taskkill.exe'
        subprocess.run([str(killer), '/PID', str(process.pid), '/T', '/F'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    else:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        if os.name != 'nt':
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            process.kill()
        process.wait(timeout=5)


def main():
    timeout = float(os.environ.get('GODOT_TEST_TIMEOUT_SECONDS', '900'))
    # Separate file handles are reopenable on Windows. Remove the temporary
    # folder only after the process tree and both handles have closed.
    with tempfile.TemporaryDirectory(prefix='godot-check-') as directory:
        path = Path(directory) / 'output.log'
        with path.open('w+b') as output, path.open('rb') as reader:
            process = subprocess.Popen(sys.argv[1:], stdout=output, stderr=subprocess.STDOUT,
                                       start_new_session=os.name != 'nt')
            start = time.monotonic()
            offset = 0
            failed = False
            failure_time = None
            tail = b''
            progress_id = None
            progress_path = os.environ.get('GODOT_TEST_PROGRESS_FILE')
            try:
                while True:
                    if progress_path:
                        try:
                            progress = json.loads(Path(progress_path).read_text())
                            if progress['id'] != progress_id:
                                progress_id = progress['id']
                                timeout = float(progress['timeout'])
                                start = time.monotonic()
                        except (OSError, ValueError, KeyError):
                            pass
                    reader.seek(offset)
                    data = reader.read()
                    offset += len(data)
                    if data:
                        sys.stdout.buffer.write(data)
                        sys.stdout.buffer.flush()
                        if ERROR_MARKER in tail + data:
                            failed = True
                            if failure_time is None:
                                failure_time = time.monotonic()
                        tail = (tail + data)[-512:]
                    expired = time.monotonic() - start > timeout
                    # Keep the following backtrace instead of killing the
                    # engine between its error heading and source location.
                    if (failed and time.monotonic() - failure_time >= 0.25) or expired:
                        if not failed:
                            print(f'ERROR: Godot check exceeded {timeout:g} seconds', flush=True)
                        stop_process(process)
                        reader.seek(offset)
                        sys.stdout.buffer.write(reader.read())
                        return 1
                    status = process.poll()
                    if status is not None:
                        reader.seek(offset)
                        data = reader.read()
                        sys.stdout.buffer.write(data)
                        return 1 if failed or ERROR_MARKER in tail + data else status
                    time.sleep(0.05)
            finally:
                stop_process(process)


if __name__ == '__main__':
    sys.exit(main())
