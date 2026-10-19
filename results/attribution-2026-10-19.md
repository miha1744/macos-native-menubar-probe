# Launch attribution: A-B-A observations

Arm64 run [39281298640](https://github.com/miha1744/macos-native-menubar-probe/actions/runs/39281298640), source `7188720c34fdb16f4fad548bd1b91bd37598d198`, and Intel run [39282375519](https://github.com/miha1744/macos-native-menubar-probe/actions/runs/39282375519), source `597a147bf998c94606064db32a60018a0450e13b`, 19 October 2026. The recorded outcome is **MEASUREMENT**, not a backend acceptance or a Jump Desktop result.

The same own ScreenCaptureKit probe was launched in three independent sessions: A1 through LaunchServices as a GUI app; B through Apple Terminal opening a `.command`, which started a detached `/usr/bin/screen` session containing the capture Mach-O; then A2 through LaunchServices again. No visibility preference was changed. Capture permission for the probe and Terminal was provisioned only in these disposable hosted VMs.

| Actual macOS | Architecture | Native target at 24s, A1 / B / A2 | B complete frames at 8s → 24s | B animated changes at 8s → 24s | Recorded outcome |
| --- | --- | --- | --- | --- | --- |
| 14.8.9 (23J631) | arm64 | visible / absent / visible | 44 → 128 | 39 → 120 | MEASUREMENT |
| 15.7.9 (24G830) | arm64 | visible / absent / visible | 40 → 125 | 39 → 121 | MEASUREMENT |
| 26.6.2 (25G83) | arm64 | visible / absent / visible | 50 → 134 | 42 → 122 | MEASUREMENT |
| 15.7.9 (24G830) | x86_64 | visible / absent / visible | 47 → 131 | 42 → 122 | MEASUREMENT |

All phases passed their actual capture-permission preflight. At 8, 16, and 24 seconds, A1/A2 each recorded one visible target and B recorded no target rectangles. Complete frames and animated-region pixel changes continued increasing, with no recorded stream error. The twelve native 24-second screenshots were manually reviewed: they match the visible / absent / visible metadata pattern. The separate stream crops are preserved too; a stream crop alone is not evidence of the native menu-bar state.

`targetPurplePixels` counts only inside the detected `targetRects`. An empty rectangle list reduces that count to zero, so B's zero is **not an independent pixel measurement of absence**. The absence observation above rests on the manually inspected native screenshot together with the target metadata.

The runner sent TERM only to the newly started Terminal after B's first sample. Each preserved `B/terminal-after-term.txt` is an empty, zero-byte process observation. The later 16/24-second B samples still show changing capture and an absent target. This establishes the recorded process observation and continuing capture; it does not identify the TCC responsible process through a dedicated API. B's stream started while Terminal was running. **Starting a new capture after Terminal has exited was not tested in these runs.**

All four VMs reported **SIP disabled**. These are observations of the probe's **own SCStream**, not a connected Jump Desktop session, its root capture helper, a shipped QuietBar backend, or acceptance on ordinary SIP-enabled Macs. They do not cover the recipient's exact Sonoma 14.6.1, macOS 13, Intel macOS 14/26, every minor release, or future builds. Opening an application successfully is a separate check from removing an indicator while a real stream continues.

## Preserved evidence

[Machine-readable summary](attribution-2026-10-19/summary.json) and raw results are retained in the repository so CI artifact expiry does not remove them. The selection contains only OS/architecture/SIP facts, attribution/capture JSON, native and stream 24-second menu-bar PNGs, and the empty Terminal-after-TERM observation. It contains no TCC database, permission-setup output, full-screen image, environment dump, or unrelated logs.

| macOS | Raw attribution JSON | Native A1, 24s | Native B, 24s | Native A2, 24s | Terminal after TERM |
| --- | --- | --- | --- | --- | --- |
| 14 | [JSON](attribution-2026-10-19/macos-14/attribution-result.json) | [visible](attribution-2026-10-19/macos-14/A1/sample-24s-system-menubar.png) | [absent](attribution-2026-10-19/macos-14/B/sample-24s-system-menubar.png) | [visible](attribution-2026-10-19/macos-14/A2/sample-24s-system-menubar.png) | [empty](attribution-2026-10-19/macos-14/B/terminal-after-term.txt) |
| 15 | [JSON](attribution-2026-10-19/macos-15/attribution-result.json) | [visible](attribution-2026-10-19/macos-15/A1/sample-24s-system-menubar.png) | [absent](attribution-2026-10-19/macos-15/B/sample-24s-system-menubar.png) | [visible](attribution-2026-10-19/macos-15/A2/sample-24s-system-menubar.png) | [empty](attribution-2026-10-19/macos-15/B/terminal-after-term.txt) |
| 26 | [JSON](attribution-2026-10-19/macos-26/attribution-result.json) | [visible](attribution-2026-10-19/macos-26/A1/sample-24s-system-menubar.png) | [absent](attribution-2026-10-19/macos-26/B/sample-24s-system-menubar.png) | [visible](attribution-2026-10-19/macos-26/A2/sample-24s-system-menubar.png) | [empty](attribution-2026-10-19/macos-26/B/terminal-after-term.txt) |
| 15 Intel | [JSON](attribution-2026-10-19/macos-15-intel/attribution-result.json) | [visible](attribution-2026-10-19/macos-15-intel/A1/sample-24s-system-menubar.png) | [absent](attribution-2026-10-19/macos-15-intel/B/sample-24s-system-menubar.png) | [visible](attribution-2026-10-19/macos-15-intel/A2/sample-24s-system-menubar.png) | [empty](attribution-2026-10-19/macos-15-intel/B/terminal-after-term.txt) |

See [experiment protocol and its limitations](../ci/ATTRIBUTION.md). The independent [native visibility preference test](preference-2026-10-19.md), including Intel macOS 15, remained negative; it is a different experiment.
