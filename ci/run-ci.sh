#!/bin/bash
set -euo pipefail
umask 077
export LC_ALL=C
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS && "$EUID" != 0 ]] || {
  printf 'Refusing: this integration runner only executes in an ephemeral GitHub-hosted macOS job.\n' >&2; exit 64;
}
QB_BASE=$(cd "$(dirname "$0")" && pwd)
QB_ROOT="${RUNNER_TEMP:?}/quietbar-native-ci"
QB_STATE="$QB_ROOT/evidence"
/bin/mkdir -p "$QB_STATE"
# A second copy in the same VM must not race an outstanding restoration.
/bin/mkdir "$QB_ROOT/single-run" || exit 64
QB_ARMED=0
QB_WATCHDOG=''
QB_OPEN=''
qb_cleanup() {
  QB_EXIT=$?
  trap - EXIT INT TERM HUP
  if [[ "$QB_ARMED" == 1 ]]; then
    if /bin/bash "$QB_BASE/restore.sh" "$QB_STATE" 0 >> "$QB_STATE/restoration.log" 2>&1; then
      [[ -z "$QB_WATCHDOG" ]] || /bin/kill -TERM "$QB_WATCHDOG" 2>/dev/null || true
    else QB_EXIT=1; fi
  fi
  if [[ -n "$QB_OPEN" ]]; then /bin/kill -TERM "$QB_OPEN" 2>/dev/null || true; fi
  exit "$QB_EXIT"
}
trap qb_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
/usr/bin/sw_vers > "$QB_STATE/os.txt"
/usr/bin/uname -m > "$QB_STATE/architecture.txt"
/usr/bin/csrutil status > "$QB_STATE/sip-status.txt" 2>&1 || true
printf '%s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}" > "$QB_STATE/image.txt"
QB_CONSOLE=$(/usr/bin/stat -f %u /dev/console)
if [[ "$QB_CONSOLE" != "$(/usr/bin/id -u)" ]] || ! /usr/bin/pgrep -x -u "$QB_CONSOLE" ControlCenter >/dev/null; then
  printf '{"status":"INCONCLUSIVE","reason":"No matching Aqua console user and ControlCenter"}\n' > "$QB_STATE/runner-result.json"
  exit 0
fi
/bin/bash "$QB_BASE/build.sh" "$QB_ROOT/build" > "$QB_STATE/build.log" 2>&1
QB_APP="$QB_ROOT/build/QuietBarCaptureProbe.app"
# Ephemeral VM provisioning is separate from product behavior. Even after this
# attempt, the GUI app must independently pass its actual permission preflight.
/bin/bash "$QB_BASE/setup-ci-permission.sh" "$QB_APP" > "$QB_STATE/permission-setup.log" 2>&1 || true
/usr/bin/open -W -n --stdout "$QB_STATE/app-stdout.log" --stderr "$QB_STATE/app-stderr.log" \
  --env GITHUB_ACTIONS=true --env RUNNER_ENVIRONMENT=github-hosted --env "RUNNER_TEMP=$RUNNER_TEMP" \
  "$QB_APP" --args "$QB_STATE" &
QB_OPEN=$!
qb_wait() {
  local marker=$1 seconds=$2
  for ((QB_I=0; QB_I<seconds; QB_I++)); do
    [[ ! -e "$QB_STATE/$marker" ]] || return 0
    [[ ! -e "$QB_STATE/capture-finished" ]] || return 1
    /bin/sleep 1
  done
  return 1
}
if ! qb_wait baseline-ready 90; then
  if [[ ! -f "$QB_STATE/capture-result.json" ]]; then
    printf '{"status":"INCONCLUSIVE","reason":"GUI probe did not establish a verified visible baseline before timeout; no preference was changed"}\n' > "$QB_STATE/runner-result.json"
  fi
  exit 0
fi
QB_DOMAIN=com.apple.controlcenter
QB_KEY='NSStatusItem Visible AudioVideoModule'
if QB_TYPE=$(/usr/bin/defaults read-type "$QB_DOMAIN" "$QB_KEY" 2>&1); then
  [[ "$QB_TYPE" == *boolean* ]] || { printf '{"status":"INCONCLUSIVE","reason":"Original candidate key has unsupported type; unchanged"}\n' > "$QB_STATE/runner-result.json"; exit 0; }
  QB_VALUE=$(/usr/bin/defaults read "$QB_DOMAIN" "$QB_KEY")
  case "$QB_VALUE" in 0|1) ;; *) exit 1 ;; esac
  printf boolean > "$QB_STATE/original-kind"; printf '%s' "$QB_VALUE" > "$QB_STATE/original-value"
else
  [[ "$QB_TYPE" == *"$QB_DOMAIN"* && ( "$QB_TYPE" == *"does not exist"* || "$QB_TYPE" == *"not found"* || ( "$QB_TYPE" == *"Could not find key"* && "$QB_TYPE" == *"$QB_KEY"* ) ) ]] || exit 1
  printf absent > "$QB_STATE/original-kind"; : > "$QB_STATE/original-value"
fi
# The detached watchdog is armed before any mutation. The app never changes a key.
QB_ARMED=1
/usr/bin/nohup /bin/bash "$QB_BASE/restore.sh" "$QB_STATE" 60 > "$QB_STATE/watchdog.log" 2>&1 < /dev/null &
QB_WATCHDOG=$!
/usr/bin/defaults write "$QB_DOMAIN" "$QB_KEY" -bool false
QB_PIDS=$(/usr/bin/pgrep -x -u "$(/usr/bin/id -u)" ControlCenter || true)
for QB_PID in $QB_PIDS; do /bin/kill -TERM "$QB_PID" 2>/dev/null || true; done
/usr/bin/touch "$QB_STATE/applied"
qb_wait after-ready 40 || true
/bin/bash "$QB_BASE/restore.sh" "$QB_STATE" 0 >> "$QB_STATE/restoration.log" 2>&1
for QB_I in {1..35}; do [[ ! -e "$QB_STATE/capture-finished" ]] || break; /bin/sleep 1; done
if [[ ! -e "$QB_STATE/capture-result.json" ]]; then
  printf '{"status":"ERROR","reason":"Missing capture outcome; original preference was restored"}\n' > "$QB_STATE/runner-result.json"
  exit 1
fi
# An inconclusive capture environment remains distinguishable from a negative result.
/usr/bin/python3 - "$QB_STATE/capture-result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print('Capture integration status:', result['status'])
print('Scope: own ScreenCaptureKit stream only; Jump Desktop not tested.')
if result['status'] in ('ERROR', 'FAIL'):
    sys.exit(1)
PY
