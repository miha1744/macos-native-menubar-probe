# Delayed child: capture starts after Terminal exits

Run [39283238857](https://github.com/miha1744/macos-native-menubar-probe/actions/runs/39283238857), source [416152396735d2381010a3a6980c2b81b8c8c957](https://github.com/miha1744/macos-native-menubar-probe/tree/416152396735d2381010a3a6980c2b81b8c8c957), 19 October 2026. Result: **MEASUREMENT — VISIBLE_ABSENT_VISIBLE_DELAYED_CHILD** on all four configurations.

The verified trace is **Terminal → detached screen → a surviving Python waiting launcher → fork/exec a new own ScreenCaptureKit probe after Terminal exits**. It is not a Jump Desktop or distributable-backend acceptance test.

| Actual macOS / architecture | B complete frames, 8 / 16 / 24s | B animated changes, 8 / 16 / 24s | Native 24s images, A1 / B / A2 | Raw result / Terminal after exit |
| --- | --- | --- | --- | --- |
| 14.8.9 (23J631), arm64 | 44 / 86 / 125 | 41 / 83 / 122 | [visible](delayed-attribution-2026-10-19/macos-14/A1/sample-24s-system-menubar.png) / [absent](delayed-attribution-2026-10-19/macos-14/B/probe/sample-24s-system-menubar.png) / [visible](delayed-attribution-2026-10-19/macos-14/A2/sample-24s-system-menubar.png) | [JSON](delayed-attribution-2026-10-19/macos-14/attribution-result.json) / [empty](delayed-attribution-2026-10-19/macos-14/B/terminal-after-term.txt) |
| 15.7.9 (24G830), arm64 | 46 / 87 / 126 | 43 / 83 / 122 | [visible](delayed-attribution-2026-10-19/macos-15/A1/sample-24s-system-menubar.png) / [absent](delayed-attribution-2026-10-19/macos-15/B/probe/sample-24s-system-menubar.png) / [visible](delayed-attribution-2026-10-19/macos-15/A2/sample-24s-system-menubar.png) | [JSON](delayed-attribution-2026-10-19/macos-15/attribution-result.json) / [empty](delayed-attribution-2026-10-19/macos-15/B/terminal-after-term.txt) |
| 26.6.2 (25G83), arm64 | 47 / 87 / 128 | 41 / 79 / 120 | [visible](delayed-attribution-2026-10-19/macos-26/A1/sample-24s-system-menubar.png) / [absent](delayed-attribution-2026-10-19/macos-26/B/probe/sample-24s-system-menubar.png) / [visible](delayed-attribution-2026-10-19/macos-26/A2/sample-24s-system-menubar.png) | [JSON](delayed-attribution-2026-10-19/macos-26/attribution-result.json) / [empty](delayed-attribution-2026-10-19/macos-26/B/terminal-after-term.txt) |
| 15.7.9 (24G830), x86_64 | 49 / 89 / 129 | 42 / 82 / 122 | [visible](delayed-attribution-2026-10-19/macos-15-intel/A1/sample-24s-system-menubar.png) / [absent](delayed-attribution-2026-10-19/macos-15-intel/B/probe/sample-24s-system-menubar.png) / [visible](delayed-attribution-2026-10-19/macos-15-intel/A2/sample-24s-system-menubar.png) | [JSON](delayed-attribution-2026-10-19/macos-15-intel/attribution-result.json) / [empty](delayed-attribution-2026-10-19/macos-15-intel/B/terminal-after-term.txt) |

All phases passed their actual permission preflight; all 8/16/24-second observations showed continuing changing complete frames without a stream error. A1/A2 recorded one visible target; B recorded none. All twelve native 24-second images were manually reviewed. B's zero purple-pixel count is not independent proof: its target rectangle list is empty.

Chronology was independently checked against raw ready/gate/after-exit/fork/pre-exec records: Terminal exit precedes fork and pre-exec, launcher/child/Probe PIDs agree, and every child exits with code 0. Both Terminal-after-TERM and exact-PID-after-TERM files are zero bytes on all four VMs. Full raw chronology and capture records remain available under each configuration; [summary.json](delayed-attribution-2026-10-19/summary.json) includes extracted timestamps, PID agreement and the exact file selection.

The optional private PID diagnostic returned Terminal while it was alive, then self for the launcher and child. The macOS 14 [8s](delayed-attribution-2026-10-19/macos-14/B/child-responsibility-8s.json) and [16s](delayed-attribution-2026-10-19/macos-14/B/child-responsibility-16s.json) snapshots preserve the live launcher/Probe after Terminal exit. These values do not identify historical TCC attribution; Apple's [ES responsible audit token](https://developer.apple.com/documentation/endpointsecurity/es_process_t/responsible_audit_token) is a different API and permits self fallback after the responsible process exits.

Limitations:

- All four VMs had **SIP disabled** and CI-only ScreenCapture permission provisioning. Ordinary approval and SIP-enabled Macs remain untested.
- This covers one simple Python launcher, one new child and one B stream per VM. Installed Jump agents, DesktopProxy/root services, existing-process reattribution, reconnects, restarts and a production GUI/DMG remain untested.
- Exact Sonoma 14.6.1, macOS 13, Intel 14/26 and other releases are not covered.

The preserved files are unmodified copies of selected nonsecret runner evidence. No TCC database, permission-provisioning output, diagnostic log, unrelated process/window dump, full-screen image or QuietBar product source is included. See [protocol](../ci/ATTRIBUTION.md#delayed-child-after-terminal-exit), [earlier attribution observations](attribution-2026-10-19.md), and the separate [negative visibility-preference result](preference-2026-10-19.md).
