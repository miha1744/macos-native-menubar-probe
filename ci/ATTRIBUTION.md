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

A responsible-PID API was not added: the local Darwin SDK headers do not provide a verified signature for one. `process-chain.txt` contains ordinary parent PIDs; it must not be presented as TCC's responsible-process identity.
