# Native visibility preference: actual negative results

Arm64 run [39280432624](https://github.com/miha1744/macos-native-menubar-probe/actions/runs/39280432624) and Intel run [39280436425](https://github.com/miha1744/macos-native-menubar-probe/actions/runs/39280436425), source `93a9306fc07b7751d0207d53383506723c140878`, 19 October 2026.

| Actual macOS | Architecture | Target before/during/after | New complete frames during | New animated pixel changes | Outcome |
| --- | --- | --- | --- | --- | --- |
| 14.8.9 (23J631) | arm64 | visible / visible / visible | 70 | 68 | FAIL |
| 15.7.9 (24G830) | arm64 | visible / visible / visible | 70 | 67 | FAIL |
| 26.6.2 (25G83) | arm64 | visible / visible / visible | 78 | 72 | FAIL |
| 15.7.9 (24G830) | x86_64 | visible / visible / visible | 70 | 69 | FAIL |

The candidate was `com.apple.controlcenter` / `NSStatusItem Visible AudioVideoModule = false`, followed by restarting only the current user's ControlCenter. The exact original boolean or absence was restored and verified on every VM. The target remained visible in both window metadata and manually reviewed native screenshots. The active stream continued receiving changing content.

`MenuBarClient` and `MenuBarClientCore` did not load; `MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion` were absent in these runtime probes. No assessment assertion was created.

All four hosted VMs reported **SIP disabled**. These are actual negative results in those configurations, not positive compatibility acceptance for normal SIP-enabled Macs. The test used its own ScreenCaptureKit stream, not a connected Jump Desktop client. It did not test 14.6.1, macOS 13, Intel macOS 14/26, all minor releases, or future builds.

The Intel run independently recorded a continuing stream, a target visible before/during/after, and `FAIL`. Its [capture JSON](preference-2026-10-19/macos-15-intel/capture-result.json), native [before](preference-2026-10-19/macos-15-intel/before-system-menubar.png) / [during](preference-2026-10-19/macos-15-intel/after-system-menubar.png) / [after recovery](preference-2026-10-19/macos-15-intel/restored-system-menubar.png) screenshots, [original boolean type](preference-2026-10-19/macos-15-intel/original-kind) and [value](preference-2026-10-19/macos-15-intel/original-value), empty [restored marker](preference-2026-10-19/macos-15-intel/restored), and [exact-restoration log](preference-2026-10-19/macos-15-intel/restoration.log) are retained. The three Intel native screenshots were manually reviewed and show the target throughout. Its [read-only backend availability probe](preference-2026-10-19/macos-15-intel/backend-availability.json) also found neither library nor assessment class.

The initial run `39278779058` was inconclusive because a test bug discarded CGFloat-backed target bounds and the original color threshold rejected the Sonoma/Sequoia fill. It changed no visibility preference. The rerun fixed these detection errors and reached the actual candidate.

[Raw JSON and before/during/after screenshots](preference-2026-10-19/summary.json) are preserved beside this report so one-day CI artifact expiry does not remove the evidence. These observations do not establish that every possible hiding method is impossible.

The separate [A-B-A launch-attribution measurement](attribution-2026-10-19.md) changes the launch chain and makes no visibility-preference mutation; do not merge its observed pattern with this failed candidate.
