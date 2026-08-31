#!/usr/bin/env python3
"""Stream MX Master 3 input state as JSON lines.

Emits a full snapshot on every event so consumers never need to track
deltas: {"p": [pressed key codes], "r": last relative axis code or null}
"""
import errno
import fcntl
import json
import os
import struct
import sys

if len(sys.argv) < 2:
    sys.exit("usage: mxmouse-events.py /dev/input/eventN")

# struct input_event is 16 bytes (timeval) on older kernels and 24 bytes
# (timespec64) on newer ones. Probe with O_NONBLOCK so a wrong size yields
# EINVAL immediately without consuming or blocking on an event.
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK)
try:
    os.read(fd, 16)
    pattern = "<IIHhi"
except OSError as e:
    if e.errno != errno.EINVAL:
        raise
    pattern = "<QQHhi"
fcntl.fcntl(fd, fcntl.F_SETFL, 0)  # clear O_NONBLOCK, back to blocking
fd = os.fdopen(fd, "rb", buffering=0)
fmt = struct.Struct(pattern)

EV_KEY, EV_REL = 1, 2

pressed = {}
last_rel = None


def emit():
    print(json.dumps({"p": sorted(pressed), "r": last_rel}), flush=True)


emit()
while True:
    data = fd.read(fmt.size)
    if len(data) < fmt.size:
        break  # device unplugged / node gone
    _tsec, _tfrac, etype, code, value = fmt.unpack(data)
    if etype == EV_KEY:
        if value:
            pressed[code] = 1
        else:
            pressed.pop(code, None)
        emit()
    elif etype == EV_REL:
        last_rel = code
        emit()
