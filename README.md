# Native macOS menu-bar experiment

This is an isolated integration harness, not a distributable QuietBar backend. See ci/README.md for acceptance and limitations.

The preference experiment checks one native visibility key with exact recovery.
The independent responsibility experiment compares GUI launch with Apple Terminal
and screen; see ci/ATTRIBUTION.md. Both require visual evidence and an active
changing capture stream. Neither is a connected Jump Desktop acceptance test.

[Actual negative preference results on macOS 14/15/26 arm64 and macOS 15 Intel](results/preference-2026-10-19.md)
include preserved screenshots, capture JSON, and recovery evidence.

[A-B-A launch-attribution observations on macOS 14/15/26 arm64 and macOS 15 Intel](results/attribution-2026-10-19.md)
record a visible / absent / visible pattern with continuing own-stream capture.
The result remains **MEASUREMENT**: all tested hosted VMs had SIP disabled,
and neither experiment validates connected Jump Desktop or a distributable backend.
A new capture started after Terminal exits remains untested.
