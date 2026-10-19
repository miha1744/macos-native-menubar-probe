#!/bin/bash
# Independent responsibility-attribution experiment, never a Jump acceptance test.
set -euo pipefail
umask 077
export LC_ALL=C
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted && "${RUNNER_OS:-}" == macOS && "$EUID" != 0 ]] || exit 64
[[ "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ && -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" ]] || exit 64
QB_DELAYED_CAPTURE=${QB_DELAYED_CAPTURE:-0}
[[ "$QB_DELAYED_CAPTURE" == 0 || "$QB_DELAYED_CAPTURE" == 1 ]] || exit 64
QB_EXPERIMENT_MODE=terminal-exit-after-first-sample
[[ "$QB_DELAYED_CAPTURE" == 0 ]] || QB_EXPERIMENT_MODE=terminal-exit-before-forkexec
QB_BASE=$(cd "$(dirname "$0")" && pwd)
QB_ROOT="$RUNNER_TEMP/quietbar-native-ci"
QB_EVIDENCE="$QB_ROOT/evidence/attribution"
/bin/mkdir -p "$QB_EVIDENCE"
/bin/mkdir "$QB_ROOT/attribution-single-run" || exit 64
QB_APP="$QB_ROOT/build/QuietBarCaptureProbe.app"
QB_EXEC="$QB_APP/Contents/MacOS/QuietBarCaptureProbe"
QB_SESSION="qb-b-${GITHUB_RUN_ID}-$(/usr/bin/uuidgen | /usr/bin/cut -c1-8)"
QB_OPEN=''
QB_NEW_TERMINAL=''
QB_TERMINAL_QUERY_OK=1
if QB_TERMINAL_BEFORE=$(/usr/bin/pgrep -x -u "$(/usr/bin/id -u)" Terminal); then :
else
  QB_QUERY_EXIT=$?
  [[ "$QB_QUERY_EXIT" == 1 ]] || QB_TERMINAL_QUERY_OK=0
fi
printf '%s\n' "$QB_TERMINAL_BEFORE" > "$QB_EVIDENCE/terminal-before.txt"
qb_stop_probe() {
  local directory=$1 pid command
  [[ -f "$directory/app-process.json" ]] || return 0
  pid=$(/usr/bin/python3 - "$directory/app-process.json" <<'PY'
import json,sys
value=json.load(open(sys.argv[1])).get('pid')
if isinstance(value,int) and value>1: print(value)
PY
)
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  command=$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)
  # Guard PID reuse: both this exact binary path and unique phase path must match.
  [[ "$command" == *"$QB_EXEC"* && "$command" == *"$directory"* ]] || return 0
  /bin/kill -TERM "$pid" 2>/dev/null || true
}
qb_stop_new_terminal() {
  # No preexisting Terminal may be touched. Match the one newly observed process.
  [[ -z "$QB_TERMINAL_BEFORE" && "$QB_NEW_TERMINAL" =~ ^[0-9]+$ ]] || return 0
  local command
  command=$(/bin/ps -p "$QB_NEW_TERMINAL" -o comm= 2>/dev/null || true)
  [[ "$command" == */Terminal || "$command" == Terminal ]] || return 0
  /bin/kill -TERM "$QB_NEW_TERMINAL" 2>/dev/null || true
}
qb_cleanup() {
  local code=$?
  trap - EXIT INT TERM HUP
  for phase in A1 B B/probe A2; do qb_stop_probe "$QB_EVIDENCE/$phase" || true; done
  /usr/bin/screen -S "$QB_SESSION" -X quit >/dev/null 2>&1 || true
  qb_stop_new_terminal || true
  [[ -z "$QB_OPEN" ]] || /bin/kill -TERM "$QB_OPEN" 2>/dev/null || true
  exit "$code"
}
trap qb_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
qb_chain() {
  local directory=$1 pid parent i
  [[ -f "$directory/app-process.json" ]] || return 0
  pid=$(/usr/bin/python3 - "$directory/app-process.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1])).get('pid',0))
PY
)
  : > "$directory/process-chain.txt"
  for i in {1..8}; do
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || break
    /bin/ps -p "$pid" -o pid=,ppid=,comm= >> "$directory/process-chain.txt" 2>/dev/null || break
    parent=$(/bin/ps -p "$pid" -o ppid= 2>/dev/null | /usr/bin/tr -d ' ')
    [[ "$parent" != "$pid" ]] || break
    pid=$parent
  done
}
qb_wait() {
  local directory=$1 marker=$2 timeout=$3 i
  for ((i=0; i<timeout; i++)); do
    [[ ! -e "$directory/$marker" ]] || return 0
    [[ ! -e "$directory/capture-finished" ]] || return 1
    /bin/sleep 1
  done
  [[ -e "$directory/$marker" ]]
}
qb_gui_leg() {
  local phase=$1 directory="$QB_EVIDENCE/$1"
  /bin/mkdir -p "$directory"
  /usr/bin/open -W -n --stdout "$directory/app-stdout.log" --stderr "$directory/app-stderr.log" \
    --env GITHUB_ACTIONS=true --env RUNNER_ENVIRONMENT=github-hosted --env "RUNNER_TEMP=$RUNNER_TEMP" \
    --env QB_MEASURE_ONLY=1 --env "QB_ATTRIBUTION_LEG=$phase-GUI" "$QB_APP" --args "$directory" &
  QB_OPEN=$!
  qb_wait "$directory" sample-8s-ready 40 || true
  qb_chain "$directory"
  qb_wait "$directory" capture-finished 35 || true
  qb_stop_probe "$directory"
  if [[ -n "$QB_OPEN" ]]; then /bin/kill -TERM "$QB_OPEN" 2>/dev/null || true; QB_OPEN=''; fi
  /bin/sleep 3
}
qb_b_inconclusive() {
  /usr/bin/python3 - "$QB_EVIDENCE/B/probe" "$1" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); root.mkdir(parents=True,exist_ok=True)
result={'schema':1,'status':'INCONCLUSIVE','reason':sys.argv[2],
        'experimentMode':'terminal-exit-before-forkexec','delayedCaptureRequested':True,
        'captureSubject':'Own ScreenCaptureKit stream only; Jump Desktop not tested',
        'permissionPreflight':None,'samples':[]}
(root/'capture-result.json').write_text(json.dumps(result,indent=2)+'\n')
(root/'capture-finished').touch()
PY
}
qb_terminal_query() {
  local status=0
  /usr/bin/pgrep -x -u "$(/usr/bin/id -u)" Terminal > "$1" || status=$?
  [[ "$status" == 0 || "$status" == 1 ]]
}
/usr/bin/sw_vers > "$QB_EVIDENCE/os.txt"
/usr/bin/uname -m > "$QB_EVIDENCE/architecture.txt"
/usr/bin/csrutil status > "$QB_EVIDENCE/sip-status.txt" 2>&1 || true
printf '%s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}" > "$QB_EVIDENCE/image.txt"
QB_CONSOLE=$(/usr/bin/stat -f %u /dev/console)
if [[ "$QB_CONSOLE" != "$(/usr/bin/id -u)" ]] || ! /usr/bin/pgrep -x -u "$QB_CONSOLE" ControlCenter >/dev/null; then
  printf '{"status":"INCONCLUSIVE","reason":"No matching Aqua console session/ControlCenter","experimentMode":"%s","delayedCaptureRequested":%s}\n' "$QB_EXPERIMENT_MODE" "$([[ "$QB_DELAYED_CAPTURE" == 1 ]] && printf true || printf false)" > "$QB_EVIDENCE/attribution-result.json"
  exit 0
fi
/bin/bash "$QB_BASE/build.sh" "$QB_ROOT/build" > "$QB_EVIDENCE/build.log" 2>&1
/usr/bin/codesign -dvv "$QB_APP" > "$QB_EVIDENCE/codesign.txt" 2>&1
/bin/bash "$QB_BASE/setup-ci-permission.sh" "$QB_APP" > "$QB_EVIDENCE/permission-setup.log" 2>&1 || true
qb_gui_leg A1
/bin/mkdir -p "$QB_EVIDENCE/B"
QB_B_OUTPUT="$QB_EVIDENCE/B"
QB_B_CAN_LAUNCH=1
if [[ "$QB_DELAYED_CAPTURE" == 1 ]]; then
  QB_B_OUTPUT="$QB_EVIDENCE/B/probe"
  if [[ "$QB_TERMINAL_QUERY_OK" != 1 || -n "$QB_TERMINAL_BEFORE" ]]; then
    qb_b_inconclusive 'Preexisting Terminal or failed initial Terminal query; delayed B was not launched'
    QB_B_CAN_LAUNCH=0
  elif ! qb_terminal_query "$QB_EVIDENCE/B/terminal-before-launch.txt" || [[ -s "$QB_EVIDENCE/B/terminal-before-launch.txt" ]]; then
    qb_b_inconclusive 'Terminal appeared before delayed B or its absence could not be verified; B was not launched'
    QB_B_CAN_LAUNCH=0
  fi
fi
if [[ "$QB_B_CAN_LAUNCH" == 1 ]]; then
# Explicitly provision only Apple Terminal. Earlier images' bundled permission
# did not make actual B preflight succeed; no approval is assumed here.
/bin/bash "$QB_BASE/setup-ci-terminal-permission.sh" > "$QB_EVIDENCE/B/terminal-permission-setup.log" 2>&1 || true
# Generate a .command that is executed by Apple Terminal in a real GUI/TTY chain.
# Only the detached screen child's environment is supplied explicitly.
/usr/bin/python3 - "$QB_EVIDENCE/launch-B.command" "$QB_EXEC" "$QB_EVIDENCE/B" "$RUNNER_TEMP" "$QB_SESSION" "$QB_BASE" "$QB_DELAYED_CAPTURE" <<'PY'
import pathlib,shlex,sys
path,exe,out,temp,session,base,delayed=sys.argv[1:]
q=shlex.quote
flags=['GITHUB_ACTIONS=true','RUNNER_ENVIRONMENT=github-hosted','RUNNER_OS=macOS','RUNNER_TEMP='+temp,'QB_MEASURE_ONLY=1','QB_ATTRIBUTION_LEG=B-Terminal-screen']
command=[exe,out]
if delayed=='1':
    command=['/usr/bin/python3',base+'/delayed_child_launcher.py','--probe',exe,'--state-dir',out,'--gate-timeout','60','--child-timeout','60']
text='''#!/bin/bash
set -euo pipefail
umask 077
'''
text+='printf "%s\\n" "$$" > '+q(out+'/terminal-command-pid.txt')+'\n'
text+='/usr/bin/screen -dmS '+q(session)+' /usr/bin/env '+ ' '.join(map(q,flags+command))+' > '+q(out+'/screen-launch.log')+' 2>&1\n'
text+='printf "%s\\n" "screen launch returned" > '+q(out+'/screen-launch-returned')+'\n'
pathlib.Path(path).write_text(text)
pathlib.Path(path).chmod(0o700)
PY
/usr/bin/open -a /System/Applications/Utilities/Terminal.app "$QB_EVIDENCE/launch-B.command" \
  > "$QB_EVIDENCE/B/terminal-open.log" 2>&1 || true
if [[ "$QB_DELAYED_CAPTURE" == 1 ]]; then
  # The waiting launcher cannot fork Probe until the exact Terminal PID is
  # recorded alive, then independently verified absent after our explicit gate.
  QB_IDENTIFIED=0
  for QB_I in {1..10}; do
    if ! qb_terminal_query "$QB_EVIDENCE/terminal-during-B.txt"; then break; fi
    QB_TERMINAL_AFTER=$(cat "$QB_EVIDENCE/terminal-during-B.txt")
    if [[ "$QB_TERMINAL_AFTER" =~ ^[0-9]+$ ]]; then
      QB_NEW_TERMINAL=$QB_TERMINAL_AFTER
      printf '%s\n' "$QB_NEW_TERMINAL" > "$QB_EVIDENCE/B/.terminal.pid"
      /bin/mv "$QB_EVIDENCE/B/.terminal.pid" "$QB_EVIDENCE/B/terminal.pid"
      QB_IDENTIFIED=1
      break
    fi
    [[ -z "$QB_TERMINAL_AFTER" ]] || break
    /bin/sleep 1
  done
  if [[ "$QB_IDENTIFIED" != 1 ]] || ! qb_wait "$QB_EVIDENCE/B" launcher-ready.json 20; then
    qb_b_inconclusive 'New Terminal and capture-free waiting launcher were not verified; no exit gate was issued'
  else
    qb_stop_new_terminal
    /usr/bin/touch "$QB_EVIDENCE/B/new-terminal-term-requested-before-forkexec"
    QB_TERMINAL_EXITED=0
    for QB_I in {1..10}; do
      if ! qb_terminal_query "$QB_EVIDENCE/B/terminal-after-term.txt"; then break; fi
      /bin/ps -p "$QB_NEW_TERMINAL" -o pid=,comm= > "$QB_EVIDENCE/B/terminal-pid-after-term.txt" 2>/dev/null || true
      if [[ ! -s "$QB_EVIDENCE/B/terminal-after-term.txt" && ! -s "$QB_EVIDENCE/B/terminal-pid-after-term.txt" ]]; then
        QB_TERMINAL_EXITED=1
        break
      fi
      /bin/sleep 1
    done
    if [[ "$QB_TERMINAL_EXITED" != 1 ]]; then
      qb_b_inconclusive 'New Terminal did not exit or another Terminal remains; no exit gate was issued'
    else
      /usr/bin/python3 - "$QB_EVIDENCE/B/terminal-term-and-exit-confirmed" "$QB_NEW_TERMINAL" <<'PYGATE'
import datetime,json,os,pathlib,sys
target=pathlib.Path(sys.argv[1]); temporary=target.with_name('.terminal-exit-gate')
temporary.write_text(json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'terminalPID':int(sys.argv[2]),'terminalPIDAbsent':True,'allCurrentUserTerminalPIDs':[],
    'experimentMode':'terminal-exit-before-forkexec'})+'\n')
os.replace(temporary,target)
PYGATE
      qb_wait "$QB_B_OUTPUT" sample-8s-ready 40 || true
      qb_chain "$QB_B_OUTPUT"
    fi
  fi
else
qb_wait "$QB_B_OUTPUT" sample-8s-ready 40 || true
qb_chain "$QB_B_OUTPUT"
QB_TERMINAL_AFTER=$(/usr/bin/pgrep -x -u "$(/usr/bin/id -u)" Terminal || true)
printf '%s\n' "$QB_TERMINAL_AFTER" > "$QB_EVIDENCE/terminal-during-B.txt"
# Close only the Terminal process newly started by this test, and only after B
# produced its first live observation. Detached screen/capture must survive it.
if [[ -z "$QB_TERMINAL_BEFORE" && "$QB_TERMINAL_AFTER" =~ ^[0-9]+$ ]]; then
  QB_NEW_TERMINAL=$QB_TERMINAL_AFTER
  if [[ -e "$QB_EVIDENCE/B/sample-8s-ready" ]]; then
    qb_stop_new_terminal
    /usr/bin/touch "$QB_EVIDENCE/B/new-terminal-term-requested-after-8s"
    /bin/sleep 1
    /usr/bin/pgrep -x -u "$(/usr/bin/id -u)" Terminal > "$QB_EVIDENCE/B/terminal-after-term.txt" || true
  fi
fi
fi
/usr/bin/screen -ls 2>/dev/null | /usr/bin/awk -v session="$QB_SESSION" '$1 ~ /^[0-9]+\./ && substr($1,index($1,".")+1)==session { print $1 }' > "$QB_EVIDENCE/B/own-screen-session.txt" || true
qb_wait "$QB_B_OUTPUT" capture-finished 35 || true
qb_stop_probe "$QB_B_OUTPUT"
/usr/bin/screen -S "$QB_SESSION" -X quit >/dev/null 2>&1 || true
fi
# If B was denied, retain a bounded diagnostic from tccd only. Never copy a
# TCC database or dump unrelated unified logs. The predicate is limited to this
# test's bundle/launch chain and request/responsibility messages.
if /usr/bin/python3 - "$QB_B_OUTPUT/capture-result.json" <<'PYDIAG'
import json,pathlib,sys
file=pathlib.Path(sys.argv[1])
result=json.loads(file.read_text()) if file.exists() else {}
sys.exit(0 if result.get('permissionPreflight') is False else 1)
PYDIAG
then
  QB_LOG_PRIVATE="$QB_ROOT/terminal-tccd-diagnostic.tmp"
  /usr/bin/log show --last 3m --style compact --info --debug --predicate 'process == "tccd" AND (eventMessage CONTAINS[c] "local.quietbar.ci.captureprobe" OR eventMessage CONTAINS[c] "com.apple.Terminal" OR eventMessage CONTAINS[c] "/usr/bin/screen" OR eventMessage CONTAINS[c] "requesting" OR eventMessage CONTAINS[c] "responsible")' \
    > "$QB_LOG_PRIVATE" 2>&1 || true
  /usr/bin/python3 - "$QB_LOG_PRIVATE" "$QB_EVIDENCE/B/tccd-denial.log" <<'PYLOG'
import pathlib,sys
source=pathlib.Path(sys.argv[1])
# Keep the tail where B's most recent denial/responsibility is expected.
data=source.read_bytes() if source.exists() else b''
pathlib.Path(sys.argv[2]).write_bytes(data[-65536:])
PYLOG
fi
/bin/sleep 3
qb_gui_leg A2
/usr/bin/python3 - "$QB_EVIDENCE" "$QB_DELAYED_CAPTURE" "$QB_EXPERIMENT_MODE" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]); phases={}
delayed=sys.argv[2]=='1'; mode=sys.argv[3]
for phase in ('A1','B','A2'):
    directory=root/phase/('probe' if phase=='B' and delayed else '')
    file=directory/'capture-result.json'
    result=json.loads(file.read_text()) if file.exists() else {'status':'INCONCLUSIVE','reason':'No capture-result before timeout'}
    samples=result.get('samples',[])
    continuous=(result.get('status')=='MEASUREMENT' and len(samples)==3 and all(s.get('streamError') is None and s.get('imageSaved') is True for s in samples) and samples[0].get('completeFrames',0)>=5 and samples[0].get('animatedPixelChanges',0)>=3 and all(b.get('completeFrames',0)-a.get('completeFrames',0)>=5 and b.get('animatedPixelChanges',0)-a.get('animatedPixelChanges',0)>=3 for a,b in zip(samples,samples[1:])))
    visible=continuous and all(s.get('strictVisibleTargets',0)>=1 and s.get('targetPurplePixels',0)>=15 for s in samples)
    absent=continuous and all(s.get('strictVisibleTargets',1)==0 for s in samples)
    phases[phase]={'status':result.get('status'),'reason':result.get('reason'),'permissionPreflight':result.get('permissionPreflight'),'continuousChangingCapture':continuous,'strictVisible':visible,'strictAbsent':absent,'samples':samples}
chronology={'requested':delayed,'verified':False}
if delayed:
    names=['launcher-ready.json','terminal-term-and-exit-confirmed','after-terminal-exit.json','child-before-exec.json','forked.json','probe/app-process.json']
    documents={}
    try:
        from datetime import datetime
        documents={name:json.loads((root/'B'/name).read_text()) for name in names}
        ready=documents[names[0]]; gate=documents[names[1]]; exited=documents[names[2]]; child=documents[names[3]]; forked=documents[names[4]]; app=documents[names[5]]
        ready_time=datetime.fromisoformat(ready['utc']); gate_time=datetime.fromisoformat(gate['utc']); exit_time=datetime.fromisoformat(exited['utc']); child_time=datetime.fromisoformat(child['utc'])
        chronology['verified']=(ready_time<=gate_time<=exit_time<=child_time and ready['captureStarted'] is False and exited['captureStarted'] is False and child['captureStarted'] is False and
            ready['terminal']['pid']==gate['terminalPID']==exited['terminalPID'] and gate['terminalPIDAbsent'] is True and exited['terminalIdentity'] is None and exited['allCurrentUserTerminalPIDs']==[] and
            child['pid']==forked['childPID']==app['pid'] and child['parentPID']==forked['parentPID']==ready['pid'])
        chronology['records']=names
    except (OSError,ValueError,KeyError,TypeError) as error:
        chronology['reason']='Missing or invalid delayed-launch chronology: '+str(error)
pattern=phases['A1']['strictVisible'] and phases['B']['strictAbsent'] and phases['A2']['strictVisible'] and (not delayed or chronology['verified'])
pattern_name='VISIBLE_ABSENT_VISIBLE_DELAYED_CHILD' if delayed else 'VISIBLE_ABSENT_VISIBLE'
result={'status':'MEASUREMENT','observedPattern':pattern_name if pattern else 'NOT_ESTABLISHED','experimentMode':mode,'delayedCaptureRequested':delayed,'delayedLaunchChronology':chronology,'manualScreenshotReviewRequired':True,'captureSubject':'Own ScreenCaptureKit stream only; Jump Desktop/root capture service not tested','phases':phases,'preferenceMutation':False,'terminalLaunch':'Apple Terminal .command -> screen -dmS -> waiting launcher -> fork/exec same capture Mach-O' if delayed else 'Apple Terminal .command -> screen -dmS -> same capture Mach-O','primaryReport':'https://github.com/lwouis/alt-tab-macos/issues/2606#issuecomment-2351026226'}
(root/'attribution-result.json').write_text(json.dumps(result,indent=2)+'\n')
print('Attribution observations:',result['observedPattern'])
print('Own SCStream only; inspect screenshots manually; no Jump Desktop claim.')
PY
