#!/bin/bash
# TuxBlox - Linux Compatibility Layer for the Roblox Engine
# Copyright (C) 2026 TuxBlox Developers
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

# Builds localhost/tuxblox-headless:arm64 from build/native, and with a host argument also loads it
# into that host's Docker over SSH (the SSH user needs sudo there).
#   deploy/headless/build-image.sh [ssh-host]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
Here="$ROOT/deploy/headless"
Native="$ROOT/build/native"
Ctx="$ROOT/workspace/headless-image"
Image=localhost/tuxblox-headless:arm64

for f in TuxBloxLauncher studio-mcp compat/main libtuxblox; do
    [ -e "$Native/$f" ] || { echo "!! $Native/$f is missing; run: make ARCH=arm64 components" >&2; exit 1; }
done
file -L "$Native/TuxBloxLauncher" | grep -q aarch64 || { echo "!! build/native is not an arm64 build" >&2; exit 1; }

rm -rf "$Ctx" && mkdir -p "$Ctx/tuxblox"
# runtime, roblox and installers are symlinks into build/ there; in the image they are the volumes.
rsync -a --exclude=/runtime --exclude=/roblox --exclude=/installers "$Native/" "$Ctx/tuxblox/"
mkdir -p "$Ctx/tuxblox/runtime" "$Ctx/tuxblox/roblox" "$Ctx/tuxblox/installers"
cp "$Here/Containerfile" "$Here/entrypoint.sh" "$Ctx/"
chmod 755 "$Ctx/entrypoint.sh"

podman build --platform linux/arm64 -t "$Image" "$Ctx"

if [ $# -ge 1 ]; then
    echo ":: Loading $Image into Docker on $1"
    podman save "$Image" | ssh "$1" sudo docker load
fi
