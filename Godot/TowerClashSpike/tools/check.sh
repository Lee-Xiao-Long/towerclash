#!/usr/bin/env bash
# Parse/import check (mirror of check.ps1): headless import, prints only script errors/warnings.
# Full log: Godot/logs/check.log. Exit 1 on any SCRIPT ERROR / Parse Error.
# Godot binary: $GODOT, else the platform default.
set -u
TOOLS="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(dirname "$TOOLS")"
LOGDIR="$(dirname "$PROJ")/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/check.log"
if [ -z "${GODOT:-}" ]; then
  case "$(uname -s)" in
    Darwin) GODOT="/Applications/Godot.app/Contents/MacOS/Godot" ;;
    MINGW*|MSYS*|CYGWIN*) GODOT="D:/Godot/Godot_v4.7.2-stable_win64_console.exe" ;;
    *) GODOT="godot" ;;
  esac
fi
"$GODOT" --headless --path "$PROJ" --import >"$LOG" 2>&1
HITS=$(grep -E "SCRIPT ERROR|Parse Error|^ERROR|^WARNING|at: " "$LOG" | head -40)
ERRS=$(grep -cE "SCRIPT ERROR|Parse Error|^ERROR" "$LOG")
[ -n "$HITS" ] && echo "$HITS"
if [ "$ERRS" -gt 0 ]; then
  # The import log only names the dependent script; --check-only per file gives the real message.
  find "$PROJ/scripts" -name "*.gd" | while read -r f; do
    res="res://${f#"$PROJ"/}"
    msg=$("$GODOT" --headless --path "$PROJ" --check-only --script "$res" 2>&1 | grep -o "Parse Error: .*" | head -1)
    [ -n "$msg" ] && echo "  $res: $msg"
  done
fi
echo "check: errors=$ERRS log=$LOG"
[ "$ERRS" -gt 0 ] && exit 1
exit 0
