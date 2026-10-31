# The box: everything a Terminal Values member needs, in one container on
# their own computer, so nothing TV-specific is installed on the computer
# itself. The TV folder is bind-mounted in at /home/tv/terminalvalues; the
# rest of the box's state (Tailscale, Syncthing, the age key, the secrets)
# lives in a volume at /state. It runs as the member's own uid, whatever
# that is, so it has no user of its own: HOME is in /state.

FROM ghcr.io/astral-sh/uv:0.13.6 AS uv

FROM debian:trixie-slim
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
      -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
 && curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
      -o /etc/apt/sources.list.d/tailscale.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      tailscale syncthing git make age openssh-client socat tree util-linux jq \
      less nano procps \
 && apt-get purge -y gnupg && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

# passage (age-based pass), from its repository at a pinned commit: no
# distribution packages it (Debian's "passage" is an unrelated game).
ARG PASSAGE_COMMIT=4e4c5ae14be91833791d45608f50868175c1490f
RUN git clone -q https://github.com/FiloSottile/passage /tmp/passage \
 && git -C /tmp/passage checkout -q "$PASSAGE_COMMIT" \
 && make -C /tmp/passage install PREFIX=/usr/local >/dev/null \
 && rm -rf /tmp/passage

COPY --from=uv /uv /uvx /usr/local/bin/

COPY tvbox-init tvbox-user tvbox-configure tvbox-join tvbox-identity tvbox-status tvbox-pages \
     tvbox-catch-up tvbox-push tvbox-import-key /usr/local/bin/
COPY stignore /etc/tvbox/
RUN chmod 755 /usr/local/bin/tvbox-* \
 && mkdir -p /state /home/tv/terminalvalues && chmod 1777 /state

ENV HOME=/state/home \
    PASSAGE_DIR=/state/secrets \
    PASSAGE_IDENTITIES_FILE=/state/home/.passage/identities \
    UV_PROJECT_ENVIRONMENT=/state/venv
ENTRYPOINT ["/usr/local/bin/tvbox-init"]
