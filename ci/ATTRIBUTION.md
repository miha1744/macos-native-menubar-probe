# Optional launch-attribution experiment

`run-attribution-ci.sh` is a separate ephemeral-hosted-CI experiment. It does not modify the preference-test runner or workflow and does not write the AudioVideoModule visibility preference.

It compiles the same GUI probe, attempts the existing own-app CI permission provisioning, and observes three independent capture sessions:

- A1: GUI app through LaunchServices (`open -W -n`).
- B: Apple Terminal opens a generated `.command`; that shell starts a uniquely named detached `/usr/bin/screen` session containing the same capture Mach-O.
- A2: GUI app through LaunchServices again.

`QB_MEASURE_ONLY=1` selects observations at 8, 16, and 24 seconds rather than the preference mutation protocol. Every phase records actual permission preflight, complete-frame counts, changing animated-region pixels, CGWindow metadata, and separate native/stream menubar screenshots. It does not require B to have a visible target at its first sample.

Only a Terminal process newly started when no Terminal was running before the test may be sent TERM after B's first sample. Preexisting Terminal processes are left alone. Process chains, the detached session identifier, and Terminal PID observations are retained. Cleanup matches the exact own probe path and unique phase path before terminating a recorded PID, and quits only the unique screen session.

The summary remains `MEASUREMENT`, even for a visible/absent/visible pattern. Root must manually inspect screenshots. No initial visible target, a permission failure, or frozen/stopped capture cannot prove hiding. Initial capture permission for Terminal is not assumed: the actual B preflight and stream decide it.

This tests a [reported Sonoma launch-attribution behavior](https://github.com/lwouis/alt-tab-macos/issues/2606#issuecomment-2351026226). It is not a Jump Desktop recipe or an application backend: Jump may capture through a root launchd service that is unaffected by wrapping its GUI. No launchd/SIP modifications are made.


## One explicit Terminal-permission correction

`setup-ci-terminal-permission.sh` is a separate hosted-CI-only provisioner for the fixed Apple-signed `/System/Applications/Utilities/Terminal.app` / `com.apple.Terminal`. It validates the Apple anchor, creates that app's designated requirement, and writes/verifies only its exact ScreenCapture row in the system and current-user TCC stores. The own-GUI provisioner remains fixed and unchanged. The user-store grant follows the official runner image setup; no preinstalled Terminal permission is assumed after the observed B denial.

B still must pass its own actual permission preflight and changing SCStream observations. If preflight remains false, the runner saves only the last 64 KiB of three minutes of filtered `tccd` messages mentioning the test/Terminal/screen chain or request/responsibility, for diagnosis rather than another blind grant. No database dump, broad permission reset, unknown process grant, or launchd change is performed.

`process-chain.txt` contains ordinary parent PIDs; it must not be presented as TCC's responsible-process identity.

## Delayed child after Terminal exit

`QB_DELAYED_CAPTURE=1` selects a separate experiment. The manual `attribution-delayed.yml` workflow runs it on standard public `macos-14`, `macos-15`, `macos-26`, and `macos-15-intel` runners, with an eight-minute job limit and one-day artifacts. The default experiment remains unchanged: it starts B capture while Terminal is alive and requests Terminal TERM after the first sample.

Delayed mode retains the complete A1/B/A2 sequence and uses the same built capture Mach-O. B is launched through Terminal and a uniquely named detached screen session, but that session initially contains only `delayed_child_launcher.py`. The waiting launcher cannot start Probe or create an SCStream before the exit gate:

1. Both the initial and fresh pre-B Terminal query must find no current-user Terminal. Otherwise B is `INCONCLUSIVE`, without opening Terminal or launching Probe.
2. The runner opens its generated `.command` in Terminal, identifies exactly one newly created Terminal PID, and records it atomically in `B/terminal.pid`.
3. The waiting launcher verifies that PID is the current user's live Terminal, records `launcher-ready.json`, and waits without forking a capture child.
4. The runner sends TERM only to that new Terminal PID, verifies both the PID's exit and an empty current-user Terminal list, then atomically writes `terminal-term-and-exit-confirmed`. A failed query or Terminal that remains running produces `INCONCLUSIVE` and no gate.
5. The launcher independently checks both absences, records `after-terminal-exit.json`, forks, rechecks in the child, writes `child-before-exec.json`, then execs Probe. Probe's first capture-capable executable therefore starts after the recorded exit. B's ordinary 8/16/24-second observations are under **`B/probe/`**.
6. The launcher records read-only responsibility snapshots at 0.5/2/8/16 seconds and reaps its own child. Timeout/signals can terminate only its unreaped child. The runner closes only its unique screen session, then observes the normal A2 leg.

The summary records `experimentMode: terminal-exit-before-forkexec`, `delayedCaptureRequested: true`, and `delayedLaunchChronology`. A delayed pattern is named `VISIBLE_ABSENT_VISIBLE_DELAYED_CHILD` only when A1 and A2 are visible with changing capture, B is absent with changing capture, and ready/gate/exit/pre-exec times and launcher/child/Probe PIDs agree. Missing or inconsistent chronology prevents a positive delayed pattern. Screenshots still require manual review; an empty target rectangle list makes a zero purple-pixel count insufficient on its own.

This tests whether a surviving launcher can create a **new** capture child after Terminal is gone. A positive result does not establish that an already-running Jump agent can be reattributed, nor that a launchd-created Jump helper uses this ancestry. Actual Jump child creation, repeated sessions and restarts, uninterrupted remote frames, ordinary permission approval, and SIP-enabled systems require their own acceptance test. All runner SIP output is retained; SIP-disabled CI success does not establish normal-Mac compatibility.

## Optional responsibility diagnostics

The two generic CI helpers contain no QuietBar product code. `responsibility_read.py` uses the private, dynamically resolved `responsibility_get_pid_responsible_for_pid` only to read a PID. It creates no Endpoint Security client and changes no TCC, preferences, or process responsibility. The API may be absent or deny access; missing/denied values stay unknown and never become zero or an acceptance condition. It is a private diagnostic, not a public libproc API or a product backend.

Apple's public [Endpoint Security responsible audit token](https://developer.apple.com/documentation/endpointsecurity/es_process_t/responsible_audit_token) is a different surface and requires an ES client entitlement. Its documentation allows fallback to self when the responsible process has exited; an after-exit snapshot does not prove historical TCC attribution. A public entitlement-free libproc getter for this identity was not established. Ordinary PPID and the optional private snapshot are recorded separately.
