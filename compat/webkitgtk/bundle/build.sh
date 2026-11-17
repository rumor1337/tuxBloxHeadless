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

set -eo pipefail
cd "$(dirname "$0")"

# TUXBLOX_ARCH (x86_64 or arm64) and, for arm64, TUXBLOX_BUILDER_BASE come from the top-level Makefile.
ARCH="${TUXBLOX_ARCH:-x86_64}"
if [ "$ARCH" = arm64 ]; then
    Image=tuxblox-webkitgtk-builder-arm64
    Vol=-arm64
    ImageArgs=(--platform linux/arm64 --build-arg "BASE=${TUXBLOX_BUILDER_BASE:?set by make ARCH=arm64}"
               --build-arg DEBIAN_ARCHIVE=0 --build-arg GCC_FIRST=1)
else
    Image=tuxblox-webkitgtk-builder
    Vol=
    ImageArgs=()
fi

echo ":: Building builder container image"
podman build "${ImageArgs[@]}" -t "$Image" -f Containerfile .

echo ":: Verifying source archives"
if [ ! -f sha256sums ]; then
    echo "ERROR: no sha256sums in this directory." >&2
    echo "       Run ./fetch-sources.sh --relock to record one." >&2
    exit 1
fi
if ! ./fetch-sources.sh --verify; then
    echo "ERROR: sources/ is incomplete, or an archive does not match sha256sums." >&2
    echo "       Run ./fetch-sources.sh to fill it, then start this again." >&2
    exit 1
fi

echo ":: Running dependency + webkitgtk build (this takes a long time -- hours on a
::    from-scratch run; much faster on a re-run since WebKitGTK's own source+build
::    tree persists in the webkitgtk-src-build volume -- ninja does a true
::    incremental build and finishes in seconds if nothing in webkitgtk itself
::    changed, see build-in-container.sh's webkitgtk section)"
# Empty file: the real header is mounted over it below.
podman run --rm --network=none -v "$(pwd):/src:ro" -v "webkitgtk-prefix$Vol:/opt/tuxblox-webview" \
    -v "$(pwd)/../../wine/dlls/webview2loader/webview2loader_ipc_protocol.h:/src/host/webview2loader_ipc_protocol.h:ro" \
    -v "$(pwd)/../src:/src-webkitgtk:ro" \
    -v "$(pwd)/sources:/sources:ro" \
    -v "webkitgtk-ccache$Vol:/ccache" -v "webkitgtk-src-build$Vol:/build/webkitgtk" -e JOBS="${JOBS:-4}" \
    "$Image" bash -c \
    "mkdir -p /build-scripts && cp /src/*.sh /src/versions.env /src/sha256sums /src/sources.list /build-scripts/ && \
     bash /build-scripts/build-in-container.sh"

echo ":: Packaging"
mkdir -p out
# The tarball's own checksum is what a manifest would lock, so it must not carry the hour it was built.
: "${SOURCE_DATE_EPOCH:=$(git -C "$(pwd)" log -1 --format=%ct 2>/dev/null || date +%s)}"
podman run --rm -v "webkitgtk-prefix$Vol:/opt/tuxblox-webview" -v "$(pwd)/out:/out" \
    -v "$(pwd)/package.sh:/build-scripts/package.sh:ro" \
    -v "$(pwd)/versions.env:/build-scripts/versions.env:ro" \
    -v "$(pwd)/../../../shared/tools/check-archive.py:/build-scripts/check-archive.py:ro" \
    -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    "$Image" bash /build-scripts/package.sh

source versions.env
echo ":: Done. Output: out/webkitgtk-${WEBKITGTK_VERSION}-${ARCH}.tar.xz"
echo ":: make webkitgtk moves it into ../prebuilt/ for you. It is gitignored: do not commit it."
