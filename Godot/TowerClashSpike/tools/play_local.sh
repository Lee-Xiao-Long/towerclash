#!/usr/bin/env bash
# Spins up the TowerClash spike locally on macOS/Linux (mirror of play_local.ps1): one headless
# dedicated server plus N windowed clients running the full app flow. Logs go to
# Godot/logs/play_<stamp>/ (one file per process); the terminal gets a short summary.
#
#   ./play_local.sh                      # server + 2 bot clients, EOS if credentials exist, loop forever
#   ./play_local.sh --bots 1             # you play client 0 against a bot
#   ./play_local.sh --bots 0             # two manual clients (press PvP in both)
#   ./play_local.sh --local              # no EOS: clients connect straight to 127.0.0.1
#   ./play_local.sh --loops 2 --wait     # unattended: bots play 2 matches, then summary
#   ./play_local.sh --stop               # close everything the last launch started
# Cross-machine (LAN) play:
#   ./play_local.sh --server-only --eos --public-address 192.168.0.16   # host here, advertise via EOS
#   ./play_local.sh --clients 1 --bots 0 --no-server                    # join via EOS session search
#   ./play_local.sh --clients 1 --bots 0 --no-server --connect 192.168.0.16:7777   # join directly
# Options: --clients N --bots N --port P --timescale X --profile-prefix S --timeout S
#          --devauth HOST:PORT [--devcred-prefix S]   (EOS DevAuthTool login, credential S<i>)
# Godot binary: $GODOT, else the platform default below.
set -u

CLIENTS=2; BOTS=2; LOCAL=0; FORCE_EOS=0; LOOPS=0; PORT=7777; TIMESCALE=1; WAIT=0; TIMEOUT=900
STOP=0; SERVER_ONLY=0; NO_SERVER=0; CONNECT=""; PUBLIC_ADDR=""; PREFIX="client"; DEVAUTH=""; DEVCRED="Player"

while [ $# -gt 0 ]; do
  case "$1" in
    --clients) CLIENTS="$2"; shift ;;
    --bots) BOTS="$2"; shift ;;
    --local) LOCAL=1 ;;
    --eos) FORCE_EOS=1 ;;
    --loops) LOOPS="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    --timescale) TIMESCALE="$2"; shift ;;
    --wait) WAIT=1 ;;
    --timeout) TIMEOUT="$2"; shift ;;
    --stop) STOP=1 ;;
    --server-only) SERVER_ONLY=1; CLIENTS=0 ;;
    --no-server) NO_SERVER=1 ;;
    --connect) CONNECT="$2"; shift ;;
    --public-address) PUBLIC_ADDR="$2"; shift ;;
    --profile-prefix) PREFIX="$2"; shift ;;
    --devauth) DEVAUTH="$2"; shift ;;
    --devcred-prefix) DEVCRED="$2"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)"; exit 2 ;;
  esac
  shift
done

TOOLS="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(dirname "$TOOLS")"
LOGROOT="$(dirname "$PROJ")/logs"
# One tracking file per role, so a --no-server client launch does not stop a --server-only server.
ROLE=""; [ "$SERVER_ONLY" = 1 ] && ROLE="_server"; [ "$NO_SERVER" = 1 ] && ROLE="_clients"
LAST="$LOGROOT/play_last$ROLE.pids"
mkdir -p "$LOGROOT"

if [ -z "${GODOT:-}" ]; then
  case "$(uname -s)" in
    Darwin) GODOT="/Applications/Godot.app/Contents/MacOS/Godot" ;;
    MINGW*|MSYS*|CYGWIN*) GODOT="D:/Godot/Godot_v4.7.2-stable_win64_console.exe" ;;
    *) GODOT="godot" ;;
  esac
fi

stop_last() { # [pids file]
  local f="${1:-$LAST}"
  [ -f "$f" ] || { echo 0; return; }
  local n=0
  for pid in $(cat "$f"); do
    if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null && n=$((n + 1)); fi
  done
  rm -f "$f"
  echo "$n"
}
if [ "$STOP" = 1 ]; then
  N=0
  for r in "" _server _clients; do N=$((N + $(stop_last "$LOGROOT/play_last$r.pids"))); done
  echo "stopped $N process(es)"; exit 0
fi
stop_last >/dev/null

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "Godot not found at '$GODOT' - set GODOT=/path/to/Godot"; exit 2
fi

DIR="$LOGROOT/play_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DIR"

USE_EOS=0
if [ "$LOCAL" = 0 ] && [ -z "$CONNECT" ]; then
  if [ -f "$PROJ/eos_credentials.local.json" ]; then USE_EOS=1
  elif [ "$FORCE_EOS" = 1 ]; then echo "--eos given but no eos_credentials.local.json in $PROJ"; exit 2
  else echo "no eos_credentials.local.json - falling back to --local"; fi
fi

PIDS=""
start_godot() { # name, then godot args..., "--", user args...
  local name="$1"; shift
  "$GODOT" --path "$PROJ" "$@" >"$DIR/$name.log" 2>"$DIR/$name.err.log" &
  PIDS="$PIDS $!"
}

if [ "$NO_SERVER" = 0 ]; then
  SA="--server --port=$PORT --timescale=$TIMESCALE"
  [ "$USE_EOS" = 1 ] && SA="$SA --eos"
  [ -n "$PUBLIC_ADDR" ] && SA="$SA --public-address=$PUBLIC_ADDR"
  FINITE=0
  if [ "$LOOPS" -gt 0 ] && [ "$BOTS" -ge "$CLIENTS" ] && [ "$CLIENTS" -gt 0 ]; then FINITE=1; SA="$SA --max-matches=$LOOPS"; fi
  # shellcheck disable=SC2086
  start_godot server --headless -- $SA
  SERVER_PID="${PIDS##* }"
  if [ "$USE_EOS" = 1 ]; then
    for _ in $(seq 1 100); do
      grep -qE "EOS session advertised|EOS ERROR" "$DIR/server.log" 2>/dev/null && break
      sleep 0.3
    done
    grep -q "EOS ERROR" "$DIR/server.log" && echo "server EOS error: $(grep -m1 'EOS ERROR' "$DIR/server.log")"
  else
    sleep 0.8
  fi
fi

i=0
while [ "$i" -lt "$CLIENTS" ]; do
  IS_BOT=0; [ "$i" -ge $((CLIENTS - BOTS)) ] && IS_BOT=1
  if [ "$IS_BOT" = 1 ]; then NAME="Bot$i"; else NAME="Player$i"; fi
  UA="--profile=$PREFIX$i --name=$NAME"
  if [ "$IS_BOT" = 1 ]; then
    UA="$UA --bot --bot-speed=$TIMESCALE --mute"
    [ "$LOOPS" -gt 0 ] && UA="$UA --loops=$LOOPS"
  fi
  if [ -n "$CONNECT" ]; then UA="$UA --local=$CONNECT"
  elif [ "$USE_EOS" = 1 ]; then UA="$UA --online"
  else UA="$UA --local=127.0.0.1:$PORT"; fi
  [ -n "$DEVAUTH" ] && UA="$UA --devauth=$DEVAUTH --devcred=$DEVCRED$i"
  # shellcheck disable=SC2086
  start_godot "client$i" --position "$((40 + i * 580)),40" -- $UA
  CLIENT_PIDS="${CLIENT_PIDS:-} ${PIDS##* }"
  sleep 0.4
  i=$((i + 1))
done

echo "$PIDS" >"$LAST"
MODE="direct 127.0.0.1:$PORT"; [ "$USE_EOS" = 1 ] && MODE="EOS"; [ -n "$CONNECT" ] && MODE="direct $CONNECT"
echo "launched $([ "$NO_SERVER" = 0 ] && echo "server + ")$CLIENTS client(s) ($BOTS bot) via $MODE; logs $DIR"
if [ "$WAIT" = 0 ]; then echo "close the client windows when done, then: ./play_local.sh --stop"; exit 0; fi

# --wait: block until the clients exit (bots with --loops quit on their own), then summarise.
END=$(( $(date +%s) + TIMEOUT ))
for pid in ${CLIENT_PIDS:-}; do
  while kill -0 "$pid" 2>/dev/null && [ "$(date +%s)" -lt "$END" ]; do sleep 1; done
done
CLEAN=0
if [ "${FINITE:-0}" = 1 ]; then
  for _ in $(seq 1 20); do kill -0 "$SERVER_PID" 2>/dev/null || { CLEAN=1; break; }; sleep 1; done
fi
KILLED=$(stop_last)
PLAYED=$(cat "$DIR/server.log" 2>/dev/null | grep -c "\] SERVER RESULT ")
RECORDED=$(cat "$DIR"/client*.log 2>/dev/null | grep -cE "APP match [0-9]+ recorded")
DONE=$(cat "$DIR"/client*.log 2>/dev/null | grep -c "APP done")
ERRS=$(cat "$DIR"/*.log 2>/dev/null | grep -cE "SCRIPT ERROR|^ERROR|\] (SERVER|CLIENT[^ ]*) ERROR|EOS ERROR")
PASS=False
# Client-only runs have no server log here: count the clients' recorded matches instead.
[ "$NO_SERVER" = 1 ] && PLAYED=$((RECORDED / (CLIENTS > 0 ? CLIENTS : 1)))
if [ "$ERRS" = 0 ] && { [ "$LOOPS" = 0 ] || { [ "$DONE" = "$BOTS" ] && [ "$PLAYED" -ge "$LOOPS" ]; }; } \
    && { [ "${FINITE:-0}" = 0 ] || [ "$CLEAN" = 1 ]; }; then PASS=True; fi
echo "PASS=$PASS server_matches=$PLAYED client_records=$RECORDED bots_done=$DONE/$BOTS server_clean_exit=$CLEAN errors=$ERRS killed=$KILLED log=$DIR"
cat "$DIR"/*.log 2>/dev/null | grep -E "SCRIPT ERROR|^ERROR|EOS ERROR" | head -5
