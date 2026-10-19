#!/bin/bash
# Ephemeral hosted-VM provisioning only. Not part of QuietBar or its DMG.
set -euo pipefail
umask 077
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS && "$EUID" != 0 ]] || exit 64
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" ]] || exit 64
QB_BASE=$(cd "$(dirname "$0")" && pwd)
QB_EXPECTED="$RUNNER_TEMP/quietbar-native-ci/build/QuietBarCaptureProbe.app"
QB_APP=${1:?expected app required}
[[ "$QB_APP" == "$QB_EXPECTED" && -d "$QB_APP" && ! -L "$QB_APP" ]] || exit 64
QB_ROOT=$(/usr/bin/python3 - "$RUNNER_TEMP" <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
)
QB_ACTUAL=$(/usr/bin/python3 - "$QB_APP" <<'PY'
import os,sys
print(os.path.realpath(sys.argv[1]))
PY
)
[[ "$QB_ACTUAL" == "$QB_ROOT/quietbar-native-ci/build/QuietBarCaptureProbe.app" ]] || exit 64
[[ "$(/usr/bin/stat -f %u /dev/console)" == "$(/usr/bin/id -u)" ]] || exit 64
QB_EVIDENCE="$QB_ROOT/quietbar-native-ci/evidence"
/bin/mkdir -p "$QB_EVIDENCE"
QB_STAGE=identity
QB_DONE=0
qb_result() {
  /usr/bin/python3 - "$QB_EVIDENCE/permission-setup.json" "$1" "$2" <<'PY'
import json,sys
with open(sys.argv[1], 'w') as f:
    json.dump({'status':sys.argv[2], 'stage':sys.argv[3],
      'scope':'Ephemeral CI VM only: own GUI test app ScreenCapture permission; not a product backend',
      'service':'kTCCServiceScreenCapture','client':'local.quietbar.ci.captureprobe',
      'captureAcceptance':'Only the GUI app CGPreflightScreenCaptureAccess and live SCStream decide capture availability'},f,indent=2)
    f.write('\n')
PY
}
qb_finish() {
  QB_EXIT=$?
  if [[ "$QB_DONE" != 1 ]]; then qb_result INCONCLUSIVE "$QB_STAGE" || true; fi
  if [[ -n "${QB_WORK:-}" && -d "$QB_WORK" ]]; then
    /usr/bin/python3 - "$QB_WORK" "$QB_EVIDENCE/permission-error.log" <<'PYERR'
import pathlib,sys
root=pathlib.Path(sys.argv[1]); chunks=[]
for name in ('sqlite-error.log','verify-error.log'):
    source=root/name
    if source.is_file():
        data=source.read_bytes()[:4096]
        if data: chunks.append((name+'\n').encode()+data+b'\n')
if chunks:
    pathlib.Path(sys.argv[2]).write_bytes(b''.join(chunks)[:4096])
PYERR
  fi
  # Provisioning failure is recorded, then the app independently checks actual
  # permission. Never turn setup success into capture acceptance.
  [[ "$QB_EXIT" == 0 ]] || printf 'CI capture permission provisioning inconclusive at %s.\n' "$QB_STAGE" >&2
}
trap qb_finish EXIT
QB_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$QB_APP/Contents/Info.plist")
[[ "$QB_ID" == local.quietbar.ci.captureprobe ]]
/usr/bin/codesign --verify --strict "$QB_APP" >/dev/null 2>&1
QB_WORK=$(/usr/bin/mktemp -d "$QB_ROOT/quietbar-native-ci/permission.XXXXXX")
# These temporary files contain only this freshly built app's requirement/SQL.
# They are outside the uploaded evidence directory. The TCC DB is never copied.
QB_STAGE=requirement
QB_REQUIREMENT=$(/usr/bin/codesign -d -r- "$QB_APP" 2>&1 | /usr/bin/sed -n -e 's/^# designated => //p' -e 's/^designated => //p')
[[ -n "$QB_REQUIREMENT" && "$QB_REQUIREMENT" != *$'\n'* ]]
/usr/bin/csreq -r "=$QB_REQUIREMENT" -b "$QB_WORK/requirement.csreq"
QB_HEX=$(/usr/bin/od -An -v -tx1 "$QB_WORK/requirement.csreq" | /usr/bin/tr -d ' \n')
[[ "$QB_HEX" =~ ^[0-9a-f]+$ ]]
QB_TIMESTAMP=$(/bin/date +%s)
[[ "$QB_TIMESTAMP" =~ ^[0-9]+$ ]]
/usr/bin/sed -e "s/__QB_CSREQ_HEX__/$QB_HEX/g" -e "s/__QB_TIMESTAMP__/$QB_TIMESTAMP/g" \
  "$QB_BASE/tcc-permission.sql.in" > "$QB_WORK/permission.sql"
QB_STAGE=system-tcc-write
QB_DB='/Library/Application Support/com.apple.TCC/TCC.db'
# Mirrors the official runner image's VM provisioning, narrowed to one exact
# service/bundle/client_type/indirect-object row. No broad reset or DB dump.
/usr/bin/sudo -n /usr/bin/sqlite3 "$QB_DB" < "$QB_WORK/permission.sql" > "$QB_WORK/sqlite-output.log" 2> "$QB_WORK/sqlite-error.log"
QB_STAGE=own-row-verification
QB_COUNT=$(/usr/bin/sudo -n /usr/bin/sqlite3 "$QB_DB" "SELECT count(*) FROM access WHERE service='kTCCServiceScreenCapture' AND client='local.quietbar.ci.captureprobe' AND client_type=0 AND indirect_object_identifier='UNUSED' AND auth_value=2 AND auth_reason=4 AND hex(csreq)=upper('$QB_HEX');" 2> "$QB_WORK/verify-error.log")
[[ "$QB_COUNT" == 1 ]]
qb_result PROVISIONED own-row-verification
QB_DONE=1
printf 'Ephemeral CI capture permission provisioned for the test app only.\n'
