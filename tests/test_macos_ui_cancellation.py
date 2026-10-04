"""Exercise cancellation before enabling any mutating backend modes."""
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WorkerCancellationTests(unittest.TestCase):
    def test_cancellation_stops_term_resistant_grandchild_and_reaps_worker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            writer = root / 'writer.py'
            marker = root / 'writes'
            pidfile = root / 'pid'
            writer.write_text('import os,signal,time,sys\n'
                              'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                              'open(sys.argv[2], "w").write(str(os.getpid()))\n'
                              'while True:\n'
                              ' with open(sys.argv[1], "a") as f: f.write("x")\n'
                              ' time.sleep(.01)\n')
            runner = root / 'runner.py'
            runner.write_text(f'import sys,signal\nsys.path.insert(0,{str(ROOT / "macos/ui-json")!r})\n'
                              'from processes import Workers,Cancelled\nw=Workers()\n'
                              'signal.signal(signal.SIGTERM,w.cancel)\n'
                              'try:\n'
                              f' w.run(["/bin/bash","-c", \'"{sys.executable}" "{writer}" "{marker}" "{pidfile}" & wait\'])\n'
                              'except Cancelled: sys.exit(2)\n')
            process = subprocess.Popen([sys.executable, str(runner)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                for _ in range(300):
                    if pidfile.exists() and marker.exists(): break
                    time.sleep(.01)
                self.assertTrue(marker.exists())
                process.send_signal(signal.SIGTERM)
                _, err = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 2, err)
                size = marker.stat().st_size
                time.sleep(.1)
                self.assertEqual(marker.stat().st_size, size)
                pid = int(pidfile.read_text())
                # A reparented zombie may briefly remain, but cannot execute/write.
                observed = subprocess.run(['/bin/ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, text=True)
                self.assertTrue(not observed.stdout.strip() or observed.stdout.strip().startswith('Z'), observed.stdout)
            finally:
                if process.poll() is None: process.kill()
                process.communicate()


if __name__ == '__main__': unittest.main()
