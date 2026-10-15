{ lib, runner, ... }:
let
  # writableDirectory = false
  fooReadOnly = ''
    if [ ! -f "foo" ]; then
      echo "Missing foo"
      exit 1
    elif [ "$(cat foo)" != "Foo contents" ]; then
      echo "Invalid foo contents"
      exit 1
    elif ( : >> foo ) 2>/dev/null; then
      echo "foo isn't read-only"
      exit 1
    fi
  '';
  bazReadOnly = ''
    if [ ! -f "bar/baz" ]; then
      echo "Missing bar/baz"
      exit 1
    elif [ "$(cat bar/baz)" != "Baz contents" ]; then
      echo "Invalid bar/baz contents"
      exit 1
    elif ( : >> bar/baz ) 2>/dev/null; then
      echo "bar/baz isn't read-only"
      exit 1
    fi
  '';
  directoryReadOnly = ''
    if ( touch newfile ) 2>/dev/null; then
      echo "directory isn't read-only"
      exit 1
    fi
    ${fooReadOnly}
    ${bazReadOnly}
  '';
  # writableDirectory = true
  fooReadWrite = ''
    if [ ! -f "foo" ]; then
      echo "Missing foo"
      exit 1
    elif [ "$(cat foo)" != "Foo contents" ]; then
      echo "Invalid foo contents"
      exit 1
    elif ! ( : >> foo ) 2>/dev/null; then
      echo "foo isn't writable"
      exit 1
    fi
  '';
  bazReadWrite = ''
    if [ ! -f "bar/baz" ]; then
      echo "Missing bar/baz"
      exit 1
    elif [ "$(cat bar/baz)" != "Baz contents" ]; then
      echo "Invalid bar/baz contents"
      exit 1
    elif ! ( : >> bar/baz ) 2>/dev/null; then
      echo "bar/baz isn't writable"
      exit 1
    fi
  '';
  directoryReadWrite = ''
    if ! ( touch newfile ) 2>/dev/null; then
      echo "directory isn't writable"
      exit 1
    fi
    if ! ( touch bar/newfile ) 2>/dev/null; then
      echo "bar sub-directory isn't writable"
      exit 1
    fi
    ${fooReadWrite}
    ${bazReadWrite}
  '';

  # useHome = false
  noHome = ''
    if [ "$HOME" != "/homeless-shelter" ]; then
      echo "Invalid HOME envvar"
      exit 1
    fi
  '';
  # useHome = true
  hasHome = ''
    if [ "$HOME" == "/homeless-shelter" ]; then
      echo "Invalid HOME envvar"
      exit 1
    elif [ ! -f "$HOME/.now-sandbox-test/hello" ]; then
      echo "Missing .now-sandbox-test/hello in HOME"
      exit 1
    fi
  '';

  # networkAccess = false
  noNetwork = ''
    interfaces=$(cat /proc/net/dev | tail -n +3 | awk '{ print $1 }' | sed 's/://')
    for interface in $interfaces; do
      if [ "$interface" != lo ]; then
        echo "network shouldn't be accessible"
        exit 1
      fi
    done
  '';
  # networkAccess = true
  hasNetwork = ''
    interfaces=$(cat /proc/net/dev | tail -n +3 | awk '{ print $1 }' | sed 's/://')
    for interface in $interfaces; do
      if [ "$interface" != lo ]; then
        break
      fi
    done
    if [ "$interface" == lo ]; then
      echo "network should be accessible"
      exit 1
    fi
  '';

  nixStoreProbe = ''
    nix-instantiate --eval --read-write-mode --raw -E 'builtins.toFile "now-sandbox-test-'"$$-$RANDOM$RANDOM"'" "x"'
  '';
  # writableNixStore = false
  nixStoreReadOnly = ''
    if ! ( command -v nix-instantiate ) >/dev/null; then
      echo "nix-instantiate not in PATH"
      exit 1
    elif [ -e /nix/var/nix ]; then
      echo "/nix/var/nix shouldn't be visible"
      exit 1
    fi
    export XDG_CACHE_HOME=/tmp/cache
    if ( NIX_REMOTE=daemon ${nixStoreProbe} ) >/dev/null 2>&1; then
      echo "Nix store isn't read-only"
      exit 1
    fi
  '';
  # writableNixStore = true
  nixStoreReadWrite = ''
    export XDG_CACHE_HOME=/tmp/cache
    storePath="$(${nixStoreProbe})"
    if [ -z "$storePath" ] || [ ! -e "$storePath" ]; then
      echo "Nix store isn't writable"
      exit 1
    fi
  '';
in
{
  jobs = {
    full =
      runner.matrix
        [
          { label = "job"; }
          { label = "step"; }
        ]
        (
          { label, ... }:
          let
            sandbox = true;
          in
          {
            name = "full-${label}";
            checkout = "clone";
            steps = [
              (
                {
                  run = ''
                    ${directoryReadOnly}
                    ${noHome}
                    ${noNetwork}
                    ${nixStoreReadOnly}
                  '';
                }
                // lib.optionalAttrs (label == "step") { inherit sandbox; }
              )
            ];
          }
          // lib.optionalAttrs (label == "job") { inherit sandbox; }
        );

    writableDirectory =
      runner.matrix
        [
          { label = "job"; }
          { label = "step"; }
        ]
        (
          { label, ... }:
          let
            sandbox = {
              enable = true;
              writableDirectory = true;
            };
          in
          {
            name = "writableDirectory-${label}";
            checkout = "clone";
            steps = [
              (
                {
                  run = ''
                    ${directoryReadWrite}
                    ${noHome}
                    ${noNetwork}
                    ${nixStoreReadOnly}
                  '';
                }
                // lib.optionalAttrs (label == "step") { inherit sandbox; }
              )
            ];
          }
          // lib.optionalAttrs (label == "job") { inherit sandbox; }
        );

    useHomeList =
      runner.matrix
        [
          { label = "job"; }
          { label = "step"; }
        ]
        (
          { label, ... }:
          let
            sandbox = {
              enable = true;
              useHome = [ ".now-sandbox-test" ];
            };
          in
          {
            name = "useHomeList-${label}";
            checkout = "clone";
            steps = [
              {
                sandbox = false;
                run = ''
                  mkdir -p "$HOME/.now-sandbox-test"
                  touch "$HOME/.now-sandbox-test/hello"
                '';
                teardown = ''
                  rm -rf "$HOME/.now-sandbox-test"
                '';
              }
              (
                {
                  run = ''
                    ${directoryReadOnly}
                    ${hasHome}
                    ${noNetwork}
                    ${nixStoreReadOnly}
                  '';
                }
                // lib.optionalAttrs (label == "step") { inherit sandbox; }
              )
            ];
          }
          // lib.optionalAttrs (label == "job") { inherit sandbox; }
        );

    useHome =
      runner.matrix
        [
          { label = "job"; }
          { label = "step"; }
        ]
        (
          { label, ... }:
          let
            sandbox = {
              enable = true;
              useHome = true;
            };
          in
          {
            name = "useHome-${label}";
            checkout = "clone";
            steps = [
              {
                sandbox = false;
                run = ''
                  mkdir -p "$HOME/.now-sandbox-test"
                  touch "$HOME/.now-sandbox-test/hello"
                '';
                teardown = ''
                  rm -rf "$HOME/.now-sandbox-test"
                '';
              }
              (
                {
                  run = ''
                    ${directoryReadOnly}
                    ${hasHome}
                    ${noNetwork}
                    ${nixStoreReadOnly}
                  '';
                }
                // lib.optionalAttrs (label == "step") { inherit sandbox; }
              )
            ];
          }
          // lib.optionalAttrs (label == "job") { inherit sandbox; }
        );

    networkAccess =
      runner.matrix
        [
          { label = "job"; }
          { label = "step"; }
        ]
        (
          { label, ... }:
          let
            sandbox = {
              enable = true;
              networkAccess = true;
            };
          in
          {
            name = "networkAccess-${label}";
            checkout = "clone";
            steps = [
              (
                {
                  run = ''
                    ${directoryReadOnly}
                    ${noHome}
                    ${hasNetwork}
                    ${nixStoreReadOnly}
                  '';
                }
                // lib.optionalAttrs (label == "step") { inherit sandbox; }
              )
            ];
          }
          // lib.optionalAttrs (label == "job") { inherit sandbox; }
        );

    writableNixStore =
      runner.matrix
        [
          { label = "job"; }
          { label = "step"; }
        ]
        (
          { label, ... }:
          let
            sandbox = {
              enable = true;
              writableNixStore = true;
            };
          in
          {
            name = "writableNixStore-${label}";
            checkout = "clone";
            steps = [
              (
                {
                  run = ''
                    ${directoryReadOnly}
                    ${noHome}
                    ${noNetwork}
                    ${nixStoreReadWrite}
                  '';
                }
                // lib.optionalAttrs (label == "step") { inherit sandbox; }
              )
            ];
          }
          // lib.optionalAttrs (label == "job") { inherit sandbox; }
        );
  };
}
