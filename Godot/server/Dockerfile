# TowerClash spike dedicated server (Linux export of Godot/TowerClashSpike, preset "Linux Server").
# Build context: Godot/ (see build_image.ps1). EOS credentials are NOT in the image: mount a
# server-only eos_credentials.local.json at /srv/towerclash/ at runtime (compose.yaml does this).
# libeosg (EOSG 2.3.1) needs glibc >= 2.38: Debian 12 (2.36) is too old, Debian 13 ships 2.41.
FROM debian:trixie-slim

# ca-certificates: the EOS SDK talks HTTPS to Epic's backend. tini (via --init/compose) reaps and
# forwards signals; the server ends itself with OS.kill(own pid), which PID 1 would ignore.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home --home-dir /srv/towerclash towerclash

WORKDIR /srv/towerclash
# --chown/--chmod at copy time: a later chown -R would duplicate every file into a new layer.
COPY --chown=towerclash --chmod=755 build/linux_server/TowerClashSpikeServer.x86_64 server/entrypoint.sh ./
COPY --chown=towerclash build/linux_server/TowerClashSpikeServer.pck build/linux_server/*.so ./

USER towerclash
ENV PORT=7777 PUBLIC_ADDRESS="" EOS=1 EXTRA_ARGS=""
EXPOSE 7777/udp
ENTRYPOINT ["./entrypoint.sh"]
