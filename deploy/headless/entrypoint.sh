#!/bin/sh
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

# Starts a virtual display, optionally a VNC server on it, then Studio. Studio exiting ends the
# container, and the stack's restart policy starts it again.
set -eu

rm -f /tmp/.X99-lock
Xvfb :99 -screen 0 "${SCREEN:-1920x1080x24}" -nolisten tcp &
for _ in $(seq 50); do [ -e /tmp/.X11-unix/X99 ] && break; sleep 0.1; done

# No password, so it listens inside the container only; the stack publishes it on the host's loopback
# and it is reached through an SSH tunnel. Only needed to sign in to Studio.
if [ "${VNC:-0}" = 1 ]; then
    x11vnc -display :99 -forever -shared -nopw -quiet -rfbport 5900 &
fi

exec /opt/tuxblox/TuxBloxLauncher --launch-studio
