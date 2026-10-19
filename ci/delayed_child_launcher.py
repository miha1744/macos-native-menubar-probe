#!/usr/bin/env python3
"""CI-only waiting launcher: fork/exec Probe AFTER the created Terminal exits.

This program does not terminate Terminal, alter permissions, or modify preferences.
The CI runner owns the exact Terminal PID and writes the exit gate. Only this
program's own child can be terminated on timeout. The existing Probe measures capture.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from responsibility_read import identity, snapshot


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", required=True, type=Path)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--gate-timeout", type=int, default=90)
    parser.add_argument("--child-timeout", type=int, default=75)
    args = parser.parse_args()
    if not (sys.platform == "darwin" and os.geteuid() != 0
            and os.environ.get("GITHUB_ACTIONS") == "true"
            and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and os.environ.get("RUNNER_OS") == "macOS"):
        parser.error("refusing outside a non-root ephemeral GitHub-hosted macOS job")
    temp_value = os.environ.get("RUNNER_TEMP")
    if not temp_value:
        parser.error("RUNNER_TEMP is required")
    temp = Path(temp_value).resolve(strict=True)
    state = args.state_dir.resolve()
    probe = args.probe.resolve(strict=True)
    for path in (state, probe):
        if not path.is_relative_to(temp):
            parser.error("probe and state must be within RUNNER_TEMP")
    if probe.name != "QuietBarCaptureProbe" or not os.access(probe, os.X_OK):
        parser.error("expected the built QuietBarCaptureProbe executable")
    if not 5 <= args.gate_timeout <= 180 or not 5 <= args.child_timeout <= 180:
        parser.error("timeouts must be between 5 and 180 seconds")
    state.mkdir(parents=True, exist_ok=True)
    lock = os.open(state / "launcher.lock", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(lock)
    child = None
    stop_requested = 0

    def write(name, data):
        destination = state / name
        temporary = state / ("." + name + "." + str(os.getpid()))
        temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
        os.replace(temporary, destination)

    def terminal_pids():
        result = subprocess.run(["/usr/bin/pgrep", "-x", "-u", str(os.getuid()), "Terminal"],
                                capture_output=True, text=True, check=False)
        if result.returncode not in (0, 1):
            raise RuntimeError("cannot verify Terminal absence")
        return [int(value) for value in result.stdout.split()]

    def fail(reason):
        write("launcher-result.json", {"status": "INCONCLUSIVE", "reason": reason,
              "probeWasForked": child is not None, "utc": utc()})
        return 2

    def terminated(signum, _frame):
        # Never signal from a handler: child can briefly be 0 after fork or stale
        # immediately after waitpid. The main loop owns all child lifecycle work.
        nonlocal stop_requested
        stop_requested = signum

    def stop_own_child():
        nonlocal child
        if child is None or child <= 0:
            return
        try:
            waited, _ = os.waitpid(child, os.WNOHANG)
        except ChildProcessError:
            child = None
            return
        if waited:
            child = None
            return
        # This unreaped child still belongs to us; an exit racing kill becomes
        # a zombie and cannot allow PID reuse before our subsequent waitpid.
        try:
            os.kill(child, signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            waited, _ = os.waitpid(child, os.WNOHANG)
            if waited:
                child = None
                return
            time.sleep(0.1)
        try:
            os.kill(child, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(child, 0)
        child = None

    def cancelled():
        stop_own_child()
        write("launcher-result.json", {"status": "INTERRUPTED", "utc": utc(),
              "signal": stop_requested, "jumpDesktopTested": False})
        return 128 + stop_requested

    signal.signal(signal.SIGTERM, terminated)
    signal.signal(signal.SIGINT, terminated)
    write("launcher-start.json", {"pid": os.getpid(), "utc": utc(),
          "responsibility": snapshot(os.getpid()), "captureStarted": False})
    deadline = time.monotonic() + args.gate_timeout
    pid_file = state / "terminal.pid"
    while not pid_file.is_file() and time.monotonic() < deadline:
        if stop_requested:
            return cancelled()
        time.sleep(0.1)
    if not pid_file.is_file():
        return fail("runner did not identify the newly created Terminal")
    try:
        terminal_pid = int(pid_file.read_text().strip())
    except (ValueError, OSError):
        return fail("invalid terminal.pid")
    terminal = identity(terminal_pid)
    if not (terminal and terminal["uid"] == os.getuid()
            and Path(terminal["executable"]).name == "Terminal"):
        return fail("Terminal PID was not observed alive as the current user's Terminal")
    write("launcher-ready.json", {"pid": os.getpid(), "utc": utc(),
          "terminal": terminal, "responsibility": snapshot(os.getpid()),
          "captureStarted": False})
    gate = state / "terminal-term-and-exit-confirmed"
    while time.monotonic() < deadline:
        if stop_requested:
            return cancelled()
        if gate.is_file() and identity(terminal_pid) is None and not terminal_pids():
            break
        time.sleep(0.1)
    else:
        return fail("Terminal exit gate was not verified; no Probe was launched")
    observed_exit = utc()
    write("after-terminal-exit.json", {"utc": observed_exit, "terminalPID": terminal_pid,
          "terminalIdentity": identity(terminal_pid), "allCurrentUserTerminalPIDs": terminal_pids(),
          "responsibility": snapshot(os.getpid()), "captureStarted": False})

    output = state / "probe"
    output.mkdir()
    env = dict(os.environ)
    env.update(QB_MEASURE_ONLY="1", QB_ATTRIBUTION_LEG="B-Delayed-forkexec-after-Terminal-exit")
    if stop_requested:
        return cancelled()
    # Explicit fork/exec: Python's subprocess implementation may select posix_spawn.
    child = os.fork()
    if child == 0:
        # The inherited parent handler must never interpret child==0 as kill(0).
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        if stop_requested:
            os._exit(128 + stop_requested)
        try:
            # Recheck immediately before the first capture-capable executable starts.
            if identity(terminal_pid) is not None or terminal_pids():
                os._exit(124)
            write("child-before-exec.json", {"pid": os.getpid(), "parentPID": os.getppid(),
                  "utc": utc(), "terminalExitPreviouslyObservedUTC": observed_exit,
                  "responsibility": snapshot(os.getpid()), "captureStarted": False})
            for target_fd, name in ((1, "app-stdout.log"), (2, "app-stderr.log")):
                fd = os.open(output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                os.dup2(fd, target_fd)
                os.close(fd)
            os.execve(str(probe), [str(probe), str(output)], env)
        except BaseException:
            os._exit(125)
    write("forked.json", {"childPID": child, "parentPID": os.getpid(), "utc": utc(),
          "terminalExitPreviouslyObservedUTC": observed_exit})
    deadline = time.monotonic() + args.child_timeout
    audited = set()
    start = time.monotonic()
    while time.monotonic() < deadline:
        if stop_requested:
            return cancelled()
        elapsed = time.monotonic() - start
        for at in (0.5, 2, 8, 16):
            if elapsed >= at and at not in audited:
                audited.add(at)
                write("child-responsibility-" + str(at) + "s.json", {
                      "elapsedSeconds": elapsed, "utc": utc(),
                      "terminalPIDs": terminal_pids(), "child": snapshot(child),
                      "launcher": snapshot(os.getpid())})
        waited, status = os.waitpid(child, os.WNOHANG)
        if waited:
            code = os.waitstatus_to_exitcode(status)
            child = None
            write("launcher-result.json", {"status": "MEASUREMENT_CHILD_EXITED",
                  "childExitCode": code, "utc": utc(), "terminalPIDs": terminal_pids(),
                  "captureAcceptance": "Read probe/capture-result.json and screenshots; launcher does not infer a hidden-target pass",
                  "jumpDesktopTested": False, "preferencesOrTCCModified": False})
            return 0 if code == 0 else 2
        time.sleep(0.1)
    stop_own_child()
    return fail("own Probe exceeded child timeout and was terminated")


if __name__ == "__main__":
    raise SystemExit(main())
