"""Bounded cancellation of worker groups, including grandchildren holding pipes open."""
import os
import signal
import subprocess


class Cancelled(Exception):
    pass


class Workers:
    def __init__(self):
        self.active = None
        self.cancelled = False
        self.spawning = False
        self.stopping = False
        self.interrupted_output = (b'', b'')

    def cancel(self, *_):
        if self.cancelled:
            return
        self.cancelled = True
        # Unwind communicate() before draining it again. Reentrant communicate in a
        # signal handler can discard bytes already read on system Python 3.9.
        if not self.spawning and not self.stopping:
            raise Cancelled()

    @staticmethod
    def stop(child):
        # The group ID is captured at spawn; never infer it from a reused PID.
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(child.pid, sig)
            except ProcessLookupError:
                pass
            if sig == signal.SIGTERM:
                try:
                    child.communicate(timeout=0.3)
                except subprocess.TimeoutExpired:
                    pass
        return child.communicate()

    def run(self, arguments, **kwargs):
        if self.cancelled:
            raise Cancelled()
        self.spawning = True
        try:
            child = subprocess.Popen(arguments, start_new_session=True, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
            self.active = child
        finally:
            self.spawning = False
        try:
            # A signal arriving between spawn and registration only sets the flag.
            if self.cancelled:
                raise Cancelled()
            out, err = child.communicate()
            return child.returncode, out, err
        finally:
            # Also stop any grandchildren left behind after a leader exits.
            self.stopping = True
            try:
                self.interrupted_output = self.stop(child)
            finally:
                self.active = None
                self.stopping = False
            if self.cancelled:
                raise Cancelled()
