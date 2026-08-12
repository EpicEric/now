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
  nowSandbox,
  nowScript,

  bubblewrap,
  lib,
  stdenvNoCC,
  writeShellScript,
  writeTextFile,
}:
if nowSandbox.enable then

  if stdenvNoCC.hostPlatform.isLinux then
    writeShellScript nowScript.name ''
      set -euo pipefail
      exec ${lib.getExe bubblewrap} \
        --ro-bind /nix/store /nix/store \
        ${lib.optionalString nowSandbox.writableNixStore ''
          --bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket \
          --setenv NIX_REMOTE daemon \
        ''} \
        --unshare-all \
        ${lib.optionalString nowSandbox.networkAccess ''
          --share-net \
          --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
          --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
          --ro-bind-try /etc/ssl/certs /etc/ssl/certs \
        ''} \
        ${
          if nowSandbox.writablePath then
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
          if lib.isList nowSandbox.useHome then
            builtins.concatStringsSep " " (
              map (
                dir: ''--bind "$HOME/${lib.removePrefix "/" dir}" "$HOME/${lib.removePrefix "/" dir}"''
              ) nowSandbox.useHome
            )
          else if nowSandbox.useHome then
            ''--bind "$HOME" "$HOME"''
          else
            "--dir /homeless-shelter --setenv HOME /homeless-shelter"
        } \
        --die-with-parent \
        -- ${nowScript} "$@"
    ''

  else if stdenvNoCC.hostPlatform.isDarwin then
    let
      profile = writeTextFile {
        name = "now-seatbelt-profile.sb";
        text = ''
          (version 1)
          (deny default)

          (allow process-exec)
          (allow process-fork)
          (allow signal (target self))
          (allow sysctl-read)

          (allow file-read* (subpath "/nix/store"))

          ${lib.optionalString nowSandbox.writableNixStore ''
            (allow file-read* file-write* (subpath "/nix/var/nix"))
          ''}

          (allow file-read* file-write* (subpath "/tmp"))
          (allow file-read* file-write* (subpath (param "TMPDIR")))

          (allow file-read*
            (literal "/etc/passwd")
            (literal "/etc/group")
            (literal "/etc/nix/nix.conf")
            (literal "/etc/hosts")
            (literal "/etc/resolv.conf"))
          (allow file-read* (subpath "/etc/ssl/certs"))

          (allow file-read*
            (literal "/dev/null")
            (literal "/dev/zero")
            (literal "/dev/random")
            (literal "/dev/urandom"))

          (allow file-read*
            (subpath "/usr/lib")
            (subpath "/System/Library"))

          (allow mach-lookup
            (global-name "com.apple.system.opendirectoryd.libinfo")
            (global-name "com.apple.trustd"))

          ${lib.optionalString nowSandbox.networkAccess ''
            (allow network-outbound)
            (allow network-inbound)
            (allow mach-lookup
              (global-name "com.apple.mDNSResponder"))
          ''}

          ${
            if lib.isList nowSandbox.useHome then
              "(allow file-read* file-write* ${
                builtins.concatStringsSep "\n" (
                  map (
                    dir: ''(subpath (string-append (param "HOME") "/${lib.removePrefix "/" dir}"))''
                  ) nowSandbox.useHome
                )
              })"
            else if nowSandbox.useHome then
              ''(allow file-read* file-write* (subpath (param "HOME")))''
            else
              ""
          }

          ${
            if nowSandbox.writablePath then
              ''
                (allow file-read* file-write* (subpath (param "PWD")))
              ''
            else
              ''
                (allow file-read* (subpath (param "PWD")))
              ''
          }
        '';
      };
    in
    writeShellScript nowScript.name ''
      set -euo pipefail
      exec /usr/bin/sandbox-exec \
        -D HOME="$HOME" \
        -D PWD="$PWD" \
        -D TMPDIR="''${TMPDIR:-/tmp}" \
        -f ${profile} -- ${nowScript} "$@"
    ''

  else
    throw "sandboxing is currently only supported on Linux and macOS"

else
  nowScript
