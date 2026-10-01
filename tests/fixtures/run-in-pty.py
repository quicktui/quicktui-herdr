#!/usr/bin/env python3
"""Run argv on a PTY, type one input line, and save the output.

usage: run-in-pty.py <input-or-""> <output-file> <argv...>
An empty input sends EOF. "<enter>" sends an empty line.
Exits with the child's exit status.
"""
import os
import pty
import sys

typed, out_path = sys.argv[1], sys.argv[2]
argv = sys.argv[3:]
pid, fd = pty.fork()
if pid == 0:
    os.execv(argv[0], argv)
if typed == "<enter>":
    os.write(fd, b"\n")
elif typed:
    os.write(fd, typed.encode() + b"\n")
else:
    os.write(fd, b"\x04")
chunks = []
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    chunks.append(data)
_, status = os.waitpid(pid, 0)
os.close(fd)
with open(out_path, "wb") as fh:
    fh.write(b"".join(chunks))
sys.exit(os.waitstatus_to_exitcode(status))
