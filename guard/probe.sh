#!/usr/bin/env bash
# agy hook PROBE — discovery only. Records exactly what agy hands a hook, then allows.
#
# Purpose: the hooks.json schema was reverse-engineered from strings in the agy
# binary and has NOT been confirmed against a running session. This script makes
# no assumptions: it captures stdin, argv and the AGY_/ANTIGRAVITY_ environment,
# appends one JSON record per invocation to the log, and always allows the tool
# call. Read the log, then write the real guard from evidence.
#
# Replace with agy-guard.sh once the payload shape is known.

set -uo pipefail

LOG="${AGY_GUARD_LOG:-$HOME/.agy-hook-probe.jsonl}"
STDIN_DATA="$(cat 2>/dev/null || true)"

# argv, one JSON string per element
ARGV_JSON="[]"
if [ "$#" -gt 0 ]; then
  ARGV_JSON="$(printf '%s\n' "$@" | python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in sys.stdin]))' 2>/dev/null || echo '[]')"
fi

ENV_JSON="$(env | grep -E '^(AGY|ANTIGRAVITY|GEMINI)_' | python3 -c '
import json,sys
d={}
for line in sys.stdin:
    k,_,v=line.rstrip("\n").partition("=")
    if k: d[k]=v
print(json.dumps(d))' 2>/dev/null || echo '{}')"

STDIN_JSON="$(printf '%s' "$STDIN_DATA" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')"

python3 - "$LOG" "$ARGV_JSON" "$ENV_JSON" "$STDIN_JSON" <<'PY' 2>/dev/null
import json, sys, datetime
log, argv, envj, stdinj = sys.argv[1:5]
rec = {
    "ts": datetime.datetime.now().astimezone().isoformat(),
    "cwd": __import__("os").getcwd(),
    "argv": json.loads(argv),
    "env": json.loads(envj),
    "stdin_raw": json.loads(stdinj),
}
try:
    rec["stdin_parsed"] = json.loads(rec["stdin_raw"]) if rec["stdin_raw"].strip() else None
except Exception as e:
    rec["stdin_parsed"] = None
    rec["stdin_parse_error"] = str(e)
with open(log, "a") as fh:
    fh.write(json.dumps(rec) + "\n")
PY

# Always allow. Emit the most likely "allow" shapes at once — a hook runner that
# reads JSON on stdout sees an allow verdict; one that only reads the exit code
# sees 0. Neither can block a tool call during discovery.
printf '%s\n' '{"decision":"allow","continue":true}'
exit 0
