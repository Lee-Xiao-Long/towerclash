#!/bin/sh
# Container entrypoint. Environment:
#   PORT            UDP port the server listens on (map the same port on the host)
#   PUBLIC_ADDRESS  address clients should use, advertised in the EOS session (host_address)
#   EOS             1 = advertise via EOS sessions (needs the mounted credentials), 0 = direct only
#   EXTRA_ARGS      more user args, e.g. "--max-matches=10 --timescale=1"
set -e
ARGS="--server --port=${PORT}"
if [ "${EOS}" = "1" ]; then
  if [ ! -f ./eos_credentials.local.json ]; then
    echo "EOS=1 but /srv/towerclash/eos_credentials.local.json is not mounted" >&2
    exit 2
  fi
  ARGS="$ARGS --eos"
fi
[ -n "${PUBLIC_ADDRESS}" ] && ARGS="$ARGS --public-address=${PUBLIC_ADDRESS}"
echo "starting: TowerClashSpikeServer --headless -- $ARGS $EXTRA_ARGS"
# shellcheck disable=SC2086
exec ./TowerClashSpikeServer.x86_64 --headless -- $ARGS $EXTRA_ARGS
