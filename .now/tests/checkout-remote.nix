{ runner, ... }:
let
  fooExists = ''
    if [ ! -f "foo" ]; then
      echo "Missing foo"
      exit 1
    elif [ "$(cat foo)" != "Foo contents" ]; then
      echo "Invalid foo contents"
      exit 1
    fi
  '';

  fooDoesntExist = ''
    if [ -f "foo" ]; then
      echo "foo is present"
      exit 1
    fi
  '';

  barExists = ''
    if [ ! -f "bar" ]; then
      echo "Missing bar"
      exit 1
    elif [ "$(cat bar)" != "Bar contents" ]; then
      echo "Invalid bar contents"
      exit 1
    fi
  '';

  barDoesntExist = ''
    if [ -f "bar" ]; then
      echo "bar is present"
      exit 1
    fi
  '';
in
{
  jobs = {
    default = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      checkout = "default";
      steps = [
        {
          run = ''
            ${fooExists}
            ${barExists}
          '';
        }
      ];
    };

    clone = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      checkout = "clone";
      steps = [
        {
          run = ''
            ${fooExists}
            ${barDoesntExist}
          '';
        }
      ];
    };

    none = {
      checkout = "none";
      steps = [
        {
          run = ''
            ${fooDoesntExist}
            ${barDoesntExist}
          '';
        }
      ];
    };

    all = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      checkout = "all";
      steps = [
        {
          run = ''
            ${fooExists}
            ${barExists}
          '';
        }
      ];
    };

    clone-all = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      checkout = "clone-all";
      steps = [
        {
          run = ''
            ${fooExists}
            ${barExists}
          '';
        }
      ];
    };
  };
}
