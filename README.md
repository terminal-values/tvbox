# tvbox

The box that Terminal Values members run on their own computers: one
container holding everything TV-specific (Tailscale, Syncthing, git,
passage, TV's tools), and `tv`, the command that starts it and reaches into
it. The TV folder itself stays an ordinary folder on the member's computer.

Work in progress; the member's guide is in TV's own repository.

Tests: `make test` (the host side), `make image-test` (builds the image;
`TV_RUNTIME=docker` or `podman` if you don't use Apple's `container`).
