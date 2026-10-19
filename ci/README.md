# QuietBar: real macOS integration experiment (not a product backend)

Prepared locally. No workflow was dispatched and no older OS result exists yet.

## Concrete remote scope

Copy this directory's source scripts to a private test repository as `ci/`, excluding `build/`. Copy `quietbar-native-matrix.yml` to `.github/workflows/quietbar-native-matrix.yml`. Manually dispatch once. The workflow uses three GitHub-hosted standard macOS labels (`macos-14`, `macos-15`, `macos-26`), eight minutes per job, no publishing/deployment, contents read-only, and one-day evidence retention. Repository creation, a push, and a CI dispatch are not performed by these files.

The exact OS build comes from the runner evidence. These labels do not provide the recipient's exact Sonoma 14.6.1, all historical minor versions, macOS 13, or Intel acceptance. The app is compiled for the actual architecture of each runner.

## What it tests

1. Confirms an ephemeral GitHub-hosted macOS job and the current Aqua console user/ControlCenter. The mutation runner and recovery refuse ordinary local use.
2. Builds and ad-hoc signs a small AppKit capture app. LaunchServices launches it with `open -W -n`, giving it an independent GUI responsibility identity, instead of invoking the Mach-O as a Terminal child.
3. Before launch, `setup-ci-permission.sh` provisions **only the freshly built test app's ScreenCapture permission in the disposable hosted VM**. It verifies the bundle/path/signature, builds its own designated requirement with `csreq`, and uses explicit common TCC columns and a single exact service/client/client-type/indirect-object row. This follows the [official runner-image provisioning script](https://github.com/actions/runner-images/blob/main/images/macos/scripts/build/configure-tccdb-macos.sh), without changing other clients/services, dumping the database, or resetting TCC. It requires hosted CI guards and noninteractive sudo. Failure is recorded as setup `INCONCLUSIVE`. The GUI app then independently checks actual Screen Recording permission: if missing, the capture is **INCONCLUSIVE** and the candidate visibility preference is untouched. A provisioned DB row is never accepted as proof of capture or hidden UI.

   This VM-only setup is **not shipped in QuietBar**, does not solve capture permission on another person's Mac, and makes no claim that the final app needs no permissions. It is never run on the developer host.
4. Starts an actual display `SCStream`, animates its window, counts `.complete` frames and changes in a sampled pixel hash inside the animated window. Saves menubar screenshots and top-of-display CGWindow metadata.
5. Requires a visible system-owned, named `AudioVideoModule` / `Audio and Video Controls` window, purple pixels in its bounds, an image, and moving captured content **before** changing anything. If the CI responsibility chain suppresses the initial pill or names are unavailable, this is **INCONCLUSIVE**, not success.
6. Takes a fresh exact-key snapshot. Only a boolean or absence is accepted. Arms an independent detached 60-second recovery process, then writes only `com.apple.controlcenter` / `NSStatusItem Visible AudioVideoModule = false` and restarts the current user's ControlCenter. It never restarts Jump Desktop.
7. While the same stream continues, records the target and image again. Restores the exact original boolean or absence and restarts ControlCenter, then records a third time.
8. A narrow machine `PASS_OWN_SCSTREAM` requires visible before → absent during → visible after, new complete frames, and changing pixels from the animated window. API acceptance, writing the preference, or a missing initial pill cannot pass. Evidence should also be reviewed visually.

The system screenshot is kept separately from the SCStream menubar crop because macOS can exclude a sharing indicator from captured stream content. The hash is a lightweight FNV-1a sample of the app's animated area, not a cryptographic integrity assertion.

## Recovery / limits

`restore.sh` is standalone and idempotent. Normal exit, INT/TERM/HUP, capture failure, and parent termination trigger restoration immediately or through the detached watchdog. Concurrent restore invocations serialize. A forcibly destroyed CI VM cannot preserve a preference change on any user Mac; the VM is disposable. No remote code can guarantee cleanup if the VM is frozen or killed in the middle of restoration.

The shell script has a single-run guard for one disposable job. A repeated attempt in the same VM is refused. Evidence includes the original key type/value and restoration log; it excludes TCC databases, environment dumps, tokens, full-screen images, and unrelated app data.

This validates **only the probe's own ScreenCaptureKit stream** on the exact runner build and architecture. It does **not** validate Jump Desktop, its root capture service/helper, or uninterrupted remote control. A successful own-stream result is grounds for a separate connected-Jump acceptance test, not a claim that a distributable DMG works everywhere.

## Local checks already appropriate to run

`bash build.sh` compiles/signs the GUI app without starting capture or changing preferences. `bash -n build.sh run-ci.sh restore.sh setup-ci-permission.sh` checks syntax. Running `run-ci.sh`, `restore.sh`, or `setup-ci-permission.sh` on an ordinary local host must exit 64 before mutation. Actual capture is intentionally restricted to the prepared hosted CI environment.
