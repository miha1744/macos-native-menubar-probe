#!/usr/bin/env python3
"""Read process responsibility; no Endpoint Security client or TCC changes."""
import argparse
import ctypes
import datetime
import json
import os
import subprocess
import sys


def identity(pid):
    result = subprocess.run(
        ["/bin/ps", "-p", str(pid), "-o", "pid=,ppid=,uid=,comm="],
        text=True, capture_output=True, check=False,
    )
    fields = result.stdout.strip().split(None, 3)
    if result.returncode or len(fields) != 4:
        return None
    return {"pid": int(fields[0]), "parentPID": int(fields[1]),
            "uid": int(fields[2]), "executable": fields[3]}


def snapshot(pid):
    data = {"schema": 1, "observedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "pid": pid, "process": identity(pid),
            "api": "responsibility_get_pid_responsible_for_pid (private)",
            "endpointSecurityClientCreated": False}
    try:
        function = getattr(ctypes.CDLL(None, use_errno=True),
                           "responsibility_get_pid_responsible_for_pid")
    except AttributeError:
        return {**data, "available": False, "responsiblePID": None,
                "reason": "Private symbol unavailable; attribution remains unknown"}
    function.argtypes = [ctypes.c_int]
    function.restype = ctypes.c_int
    ctypes.set_errno(0)
    responsible = function(pid)
    error = ctypes.get_errno()
    data.update(available=True, responsiblePID=responsible if responsible > 0 else None,
                rawReturn=responsible, errno=error,
                responsibleProcess=identity(responsible) if responsible > 0 else None)
    if responsible <= 0:
        data["reason"] = "Query unavailable or denied; this is not evidence of no responsibility"
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, action="append")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("macOS only")
    pids = args.pid or [os.getpid()]
    if any(pid <= 0 for pid in pids):
        parser.error("positive PIDs only")
    print(json.dumps([snapshot(pid) for pid in pids], indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
