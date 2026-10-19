#!/bin/bash
# Disposable hosted-VM setup for Apple Terminal only; never part of QuietBar.
set -euo pipefail
umask 077
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS && "$EUID" != 0 ]] || exit 64
[[ $# == 0 && "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" ]] || exit 64
QB_BASE=$(cd "$(dirname "$0")" && pwd)
QB_ROOT=$(/usr/bin/python3 - "$RUNNER_TEMP" <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
)
[[ -d "$QB_ROOT/quietbar-native-ci/attribution-single-run" && -d "$QB_ROOT/quietbar-native-ci/evidence/attribution/B" ]] || exit 64
[[ "$(/usr/bin/stat -f %u /dev/console)" == "$(/usr/bin/id -u)" ]] || exit 64
QB_EVIDENCE="$QB_ROOT/quietbar-native-ci/evidence/attribution/B"
QB_APP='/System/Applications/Utilities/Terminal.app'
QB_STAGE=apple-identity
QB_DONE=0
QB_SYSTEM=not-attempted
QB_USER=not-attempted
qb_result() {
  /usr/bin/python3 - "$QB_EVIDENCE/terminal-permission-setup.json" "$1" "$QB_STAGE" "$QB_SYSTEM" "$QB_USER" <<'PY'
import json,sys
with open(sys.argv[1],'w') as f:
    json.dump({'status':sys.argv[2],'stage':sys.argv[3],
      'client':'com.apple.Terminal','service':'kTCCServiceScreenCapture',
      'systemStore':sys.argv[4],'currentUserStore':sys.argv[5],
      'scope':'Only Apple-signed system Terminal, ephemeral CI VM; no general process permissions granted',
      'acceptance':'Provisioned rows are not capture acceptance; actual B preflight/SCStream remain authoritative'},f,indent=2)
    f.write('\n')
PY
}
qb_finish() {
  local code=$?
  if [[ "$QB_DONE" != 1 ]]; then qb_result INCONCLUSIVE || true; fi
  if [[ -n "${QB_WORK:-}" && -d "$QB_WORK" ]]; then
    /usr/bin/python3 - "$QB_WORK" "$QB_EVIDENCE/terminal-permission-error.log" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1]); chunks=[]
for name in ('system-sqlite-error.log','system-verify-error.log','user-sqlite-error.log','user-verify-error.log'):
    file=root/name
    if file.is_file():
        data=file.read_bytes()[:4096]
        if data:chunks.append((name+'\n').encode()+data+b'\n')
if chunks:pathlib.Path(sys.argv[2]).write_bytes(b''.join(chunks)[:4096])
PY
  fi
  [[ "$code" == 0 ]] || printf 'Terminal CI provisioning inconclusive at %s.\n' "$QB_STAGE" >&2
}
trap qb_finish EXIT
[[ -d "$QB_APP" && ! -L "$QB_APP" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$QB_APP/Contents/Info.plist")" == com.apple.Terminal ]]
/usr/bin/codesign --verify --strict -R='anchor apple and identifier "com.apple.Terminal"' "$QB_APP" >/dev/null 2>&1
QB_WORK=$(/usr/bin/mktemp -d "$QB_ROOT/quietbar-native-ci/terminal-permission.XXXXXX")
QB_STAGE=apple-requirement
QB_REQUIREMENT=$(/usr/bin/codesign -d -r- "$QB_APP" 2>&1 | /usr/bin/sed -n -e 's/^# designated => //p' -e 's/^designated => //p')
[[ -n "$QB_REQUIREMENT" && "$QB_REQUIREMENT" != *$'\n'* ]]
/usr/bin/csreq -r "=$QB_REQUIREMENT" -b "$QB_WORK/terminal.csreq"
QB_HEX=$(/usr/bin/od -An -v -tx1 "$QB_WORK/terminal.csreq" | /usr/bin/tr -d ' \n')
[[ "$QB_HEX" =~ ^[0-9a-f]+$ ]]
QB_TIMESTAMP=$(/bin/date +%s)
/usr/bin/python3 - "$QB_BASE/tcc-permission.sql.in" "$QB_WORK/permission.sql" "$QB_HEX" "$QB_TIMESTAMP" <<'PY'
import pathlib,re,sys
source=pathlib.Path(sys.argv[1]).read_text()
assert source.count("'local.quietbar.ci.captureprobe'")==1
assert re.fullmatch('[0-9a-f]+',sys.argv[3]) and sys.argv[4].isdigit()
source=source.replace("'local.quietbar.ci.captureprobe'","'com.apple.Terminal'")
source=source.replace('__QB_CSREQ_HEX__',sys.argv[3]).replace('__QB_TIMESTAMP__',sys.argv[4])
pathlib.Path(sys.argv[2]).write_text(source)
PY
# Official runner provisioning stores Terminal's ScreenCapture grant in the
# current-user DB. Also provision the same exact row in the system store, as
# used for the own-GUI test app; do not assume which store owns this chain.
for QB_STORE in system user; do
  QB_STAGE="$QB_STORE-tcc-write"
  if [[ "$QB_STORE" == system ]]; then
    QB_DB='/Library/Application Support/com.apple.TCC/TCC.db'
    QB_SQLITE=(/usr/bin/sudo -n /usr/bin/sqlite3 "$QB_DB")
  else
    QB_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    QB_SQLITE=(/usr/bin/sqlite3 "$QB_DB")
  fi
  QB_STATUS=INCONCLUSIVE
  if [[ -f "$QB_DB" && ! -L "$QB_DB" ]] && "${QB_SQLITE[@]}" < "$QB_WORK/permission.sql" > "$QB_WORK/$QB_STORE-sqlite-output.log" 2> "$QB_WORK/$QB_STORE-sqlite-error.log"; then
    QB_STAGE="$QB_STORE-own-row-verification"
    if QB_COUNT=$("${QB_SQLITE[@]}" "SELECT count(*) FROM access WHERE service='kTCCServiceScreenCapture' AND client='com.apple.Terminal' AND client_type=0 AND indirect_object_identifier='UNUSED' AND auth_value=2 AND auth_reason=4 AND hex(csreq)=upper('$QB_HEX');" 2> "$QB_WORK/$QB_STORE-verify-error.log") && [[ "$QB_COUNT" == 1 ]]; then QB_STATUS=PROVISIONED; fi
  fi
  if [[ "$QB_STORE" == system ]]; then QB_SYSTEM=$QB_STATUS; else QB_USER=$QB_STATUS; fi
 done
QB_STAGE=terminal-row-verification
if [[ "$QB_SYSTEM" == PROVISIONED && "$QB_USER" == PROVISIONED ]]; then qb_result PROVISIONED; else qb_result INCONCLUSIVE; fi
QB_DONE=1
printf 'Terminal CI permission setup: system=%s, user=%s. Actual capture must still pass.\n' "$QB_SYSTEM" "$QB_USER"
