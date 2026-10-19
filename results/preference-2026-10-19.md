# Native visibility preference: actual negative results

Run [39280432624](https://github.com/miha1744/macos-native-menubar-probe/actions/runs/39280432624), source `93a9306`, 19 October 2026.

| Actual macOS | Architecture | Target before/during/after | New complete frames during | New animated pixel changes | Outcome |
| --- | --- | --- | --- | --- | --- |
| 14.8.9 (23J631) | arm64 | visible / visible / visible | 70 | 68 | FAIL |
| 15.7.9 (24G830) | arm64 | visible / visible / visible | 70 | 67 | FAIL |
| 26.6.2 (25G83) | arm64 | visible / visible / visible | 78 | 72 | FAIL |

The candidate was `com.apple.controlcenter` / `NSStatusItem Visible AudioVideoModule = false`, followed by restarting only the current user's ControlCenter. The exact original boolean or absence was restored and verified on every VM. The target remained visible in both window metadata and manually reviewed native screenshots. The active stream continued receiving changing content.

`MenuBarClient` and `MenuBarClientCore` did not load; `MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion` were absent in these runtime probes. No assessment assertion was created.

All three hosted VMs reported **SIP disabled**. These are actual negative results in those configurations, not positive compatibility acceptance for normal SIP-enabled Macs. The test used its own ScreenCaptureKit stream, not a connected Jump Desktop client. It did not test 14.6.1, macOS13, Intel, all minor releases, or future builds.

The initial run `39278779058` was inconclusive because a test bug discarded CGFloat-backed target bounds and the original color threshold rejected the Sonoma/Sequoia fill. It changed no visibility preference. The rerun fixed these detection errors and reached the actual candidate.

[Raw JSON and before/during/after screenshots](preference-2026-10-19/summary.json) are preserved beside this report so one-day CI artifact expiry does not remove the evidence. These observations do not establish that every possible hiding method is impossible.
