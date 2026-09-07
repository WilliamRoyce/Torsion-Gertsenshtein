# cspell:words gmtime
"""Timestamp a byte stream line by line, for the PSALTer Tier-1 gate.

PSALTer announces its own progress: every function defined through its
``StackSetDelayed`` wrapper shells out an ``echo`` naming itself on entry
(``Sources/ParticleSpectrum/ConstructSpectrograph/CLICallStack.m``), whenever it
runs without a notebook front end. So a run already emits a stage trace, and the
only thing missing is *when* each line appeared.

Timestamping the stream rather than instrumenting the session is what lets the
gate satisfy two requirements at once: a checkpoint trace, and running the
published script byte-for-byte unmodified. Nothing here touches the kernel.

Works on bytes, never decoded text: the stream carries raw ANSI escapes and
``ParticleSpectrum`` prints a very large typeset expression on completion.
Over-long lines are truncated here and kept intact in the raw log.

Usage:
    ... | python3 stamp_lines.py [--max-line-bytes N] > run.log
"""

from __future__ import annotations

import argparse
import sys
import time

# Chosen so a stray megabyte-long typeset expression cannot bloat the log, while
# leaving real diagnostic lines untouched.
DEFAULT_MAX_LINE_BYTES = 4000


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-line-bytes", type=int, default=DEFAULT_MAX_LINE_BYTES)
    args = parser.parse_args()

    start = time.time()
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    for raw in stdin:
        now = time.time()
        line = raw.rstrip(b"\r\n")
        if args.max_line_bytes > 0 and len(line) > args.max_line_bytes:
            omitted = len(line) - args.max_line_bytes
            line = line[: args.max_line_bytes] + b"... [%d bytes omitted]" % omitted
        stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)).encode()
        stdout.write(b"%s +%09.3f %s\n" % (stamp, now - start, line))
        # Unbuffered: a checkpoint taken mid-run must see the trace so far.
        stdout.flush()

    return 0


if __name__ == "__main__":
    sys.exit(main())
