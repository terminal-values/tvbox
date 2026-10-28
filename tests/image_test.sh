#!/bin/sh
# Build the box image and check it has what TV needs.
# TV_RUNTIME is the command to run containers with: container (default),
# docker, podman, or e.g. "sudo docker".
cd "$(dirname "$0")/.." || exit 1
RT=${TV_RUNTIME:-container}
IMAGE=tvbox:dev
fails=0
ok()   { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

if ! $RT build -t "$IMAGE" box >/dev/null 2>&1; then
    fail "the image doesn't build: $RT build -t $IMAGE box"
    exit 1
fi
ok "the image builds"

run() { $RT run --rm --entrypoint /bin/sh "$@"; }

for tool in tailscale tailscaled syncthing git age age-keygen passage uv make ssh socat getopt tree; do
    if run "$IMAGE" -c "command -v $tool" >/dev/null 2>&1; then
        ok "$tool is in the box"
    else
        fail "$tool is missing"
    fi
done

if run "$IMAGE" -c 'passage version' 2>/dev/null | grep -qi passage; then
    ok "passage runs (GNU getopt is there)"
else
    fail "passage doesn't run"
fi

got=$(run --user 1234:1234 "$IMAGE" -c 'echo "$(id -u) $HOME"' 2>/dev/null)
if [ "$got" = "1234 /state/home" ]; then
    ok "it runs as any uid, with HOME in /state"
else
    fail "as uid 1234 it says '$got', want '1234 /state/home'"
fi

# Apple's container doesn't report an unpacked size; Docker and Podman do.
size=$($RT image inspect "$IMAGE" --format '{{.Size}}' 2>/dev/null)
if [ -z "$size" ]; then
    echo "skip: $RT doesn't report the image's size (check it with docker or podman)"
elif [ "$size" -lt 600000000 ]; then
    ok "the image is $((size / 1000000)) MB"
else
    fail "the image is ${size:-of unknown size} bytes, want under 600 MB"
fi
exit "$fails"
