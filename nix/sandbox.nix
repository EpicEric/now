# now: Nix-based distributed command runner
# Copyright (C) 2026 Eric Rodrigues Pires
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
# more details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

{
  sandbox,
  script,

  bubblewrap,
  lib,
  stdenvNoCC,
  writeShellScript,
}:
if sandbox.enable or false then
  if stdenvNoCC.hostPlatform.isLinux then
    writeShellScript script.name ''
      set -euo pipefail
      exec ${lib.getExe bubblewrap} \
        --ro-bind /nix/store /nix/store \
        --bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket \
        --setenv NIX_REMOTE daemon \
        ${
          if sandbox.networkAccess then
            ''
              --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
              --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
              --ro-bind-try /etc/ssl/certs /etc/ssl/certs \
            ''
          else
            "--unshare-net"
        } \
        ${
          if sandbox.writablePath then
            ''--bind "$PWD" "$PWD" --chdir "$PWD"''
          else
            ''--ro-bind "$PWD" "$PWD" --chdir "$PWD"''
        } \
        --proc /proc \
        --dev /dev \
        --tmpfs /tmp \
        --ro-bind-try /etc/passwd /etc/passwd \
        --ro-bind-try /etc/group /etc/group \
        --ro-bind-try /etc/nix/nix.conf /etc/nix/nix.conf \
        ${
          if sandbox.useHome then
            ''--bind "$HOME" "$HOME"''
          else
            "--dir /homeless-shelter --setenv HOME /homeless-shelter"
        } \
        --setenv NIX_CONFIG "experimental-features = nix-command flakes" \
        --die-with-parent \
        -- ${script} "$@"
    ''
  else
    throw "sandboxing is currently only supported on Linux"
else
  script
