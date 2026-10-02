#!/usr/bin/env python3

# SPDX-License-Identifier: GPL-3.0-or-later
"""Stop the container when a program goes FATAL.

supervisord would leave the program dead and the container running, hiding the
failure from the module's systemd unit, which restarts the container instead.

Protocol: https://supervisord.org/events.html#event-listeners-and-event-notifications
"""
import os
import signal
import sys


def write_stdout(msg: str) -> None:
    sys.stdout.write(msg)
    sys.stdout.flush()


def main() -> None:
    while True:
        write_stdout("READY\n")

        line = sys.stdin.readline()
        if not line:
            # supervisord is shutting down.
            return

        try:
            headers = dict(field.split(":", 1) for field in line.split())
            length = int(headers["len"])
            payload = sys.stdin.read(length)
        except (ValueError, KeyError) as exc:
            # Crashing here would silently disable the watchdog.
            sys.stderr.write(f"exit-on-fatal: ignoring malformed event: {exc}\n")
            sys.stderr.flush()
            write_stdout("RESULT 4\nFAIL")
            continue

        write_stdout("RESULT 2\nOK")

        if headers.get("eventname") == "PROCESS_STATE_FATAL":
            sys.stderr.write(f"exiting: a supervised process is FATAL ({payload})\n")
            sys.stderr.flush()
            os.kill(1, signal.SIGTERM)


if __name__ == "__main__":
    main()
