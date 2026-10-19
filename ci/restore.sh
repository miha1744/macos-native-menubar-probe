#!/bin/bash
# Independent, idempotent restoration. CI-only: never run against a local Mac.
set -euo pipefail
umask 077
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS && "${EUID}" != 0 ]] || exit 64
QB_STATE=${1:?state directory required}
QB_DELAY=${2:-0}
case "$QB_STATE" in "${RUNNER_TEMP:?}"/quietbar-native-ci/*) ;; *) exit 64 ;; esac
case "$QB_DELAY" in 0|60) ;; *) exit 64 ;; esac
/bin/sleep "$QB_DELAY"
[[ -f "$QB_STATE/original-kind" && -f "$QB_STATE/original-value" ]] || exit 65
[[ ! -e "$QB_STATE/restored" ]] || exit 0
if ! /bin/mkdir "$QB_STATE/restoring" 2>/dev/null; then
  for QB_TRY in {1..100}; do
    [[ ! -e "$QB_STATE/restored" ]] || exit 0
    /bin/sleep 0.1
  done
  exit 1
fi
trap '/bin/rmdir "$QB_STATE/restoring" 2>/dev/null || true' EXIT
[[ ! -e "$QB_STATE/restored" ]] || exit 0
QB_DOMAIN=com.apple.controlcenter
QB_KEY='NSStatusItem Visible AudioVideoModule'
QB_KIND=$(/bin/cat "$QB_STATE/original-kind")
QB_VALUE=$(/bin/cat "$QB_STATE/original-value")
case "$QB_KIND:$QB_VALUE" in
  boolean:0|boolean:1)
    QB_BOOL=false; [[ "$QB_VALUE" != 1 ]] || QB_BOOL=true
    /usr/bin/defaults write "$QB_DOMAIN" "$QB_KEY" -bool "$QB_BOOL"
    [[ "$(/usr/bin/defaults read-type "$QB_DOMAIN" "$QB_KEY")" == *boolean* ]]
    [[ "$(/usr/bin/defaults read "$QB_DOMAIN" "$QB_KEY")" == "$QB_VALUE" ]]
    ;;
  absent:)
    if /usr/bin/defaults read-type "$QB_DOMAIN" "$QB_KEY" >/dev/null 2>&1; then /usr/bin/defaults delete "$QB_DOMAIN" "$QB_KEY"; fi
    if QB_ERROR=$(/usr/bin/defaults read-type "$QB_DOMAIN" "$QB_KEY" 2>&1); then exit 1; fi
    [[ "$QB_ERROR" == *"$QB_DOMAIN"* && ( "$QB_ERROR" == *"does not exist"* || "$QB_ERROR" == *"not found"* || ( "$QB_ERROR" == *"Could not find key"* && "$QB_ERROR" == *"$QB_KEY"* ) ) ]]
    ;;
  *) exit 65 ;;
esac
QB_PIDS=$(/usr/bin/pgrep -x -u "$(/usr/bin/id -u)" ControlCenter || true)
for QB_PID in $QB_PIDS; do /bin/kill -TERM "$QB_PID" 2>/dev/null || true; done
/usr/bin/touch "$QB_STATE/restored"
printf 'Exact original key type/value restored.\n'
