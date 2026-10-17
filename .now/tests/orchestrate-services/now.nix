let
  services = import (import ../../../.tack).now-services;
  now = import ../../.. { };
in
{
  default = "orchestrate";

  jobs = {
    sleep = { pkgs, ... }: {
      steps = [
        {
          shell = pkgs.python313;
          run = ''
            import asyncio
            import signal
            import sys

            sys.stdout.reconfigure(line_buffering=True)

            async def shutdown(sig):
                print(f"Caught signal: {sig.name}")
                sys.exit(42)

            async def main():
                loop = asyncio.get_running_loop()
                for sig in (signal.SIGINT, signal.SIGTERM):
                    loop.add_signal_handler(sig, lambda sig=sig: asyncio.create_task(shutdown(sig)))

                print("Started main()")
                await asyncio.sleep(300)
                print("Finished main()")

            asyncio.run(main())
          '';
        }
      ];
    };

    orchestrate = {
      steps = [
        (services.orchestrate {
          env = { };
          jobs = [ "sleep" ];
          package = now;
          strategy = "terminate";
          nowArgs = [ "--logging=minimal" ];
        })
      ];
    };
  };
}
