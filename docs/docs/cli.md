---
icon: lucide/terminal
---
# CLI reference
!!! note

    This documentation is auto-generated from the command line.
## now

<pre class="terminal">
now - Nix-based distributed command runner.

<b><u>Examples:</u></b>
  <span style='opacity:0.67'># Initialize a basic workflow in ./now.nix</span>
  now init

  <span style='opacity:0.67'># Load envvars from a dotenv file and run the default job(s)</span>
  now run --env-file .env

  <span style='opacity:0.67'># Run the &quot;deploy&quot; job (and all dependencies) from the specified workflow,
  # and specify a remote builder for the run</span>
  now run deploy \
    --builders &quot;ssh://mac aarch64-darwin&quot; \
    --workflow .now/remote.nix

  <span style='opacity:0.67'># Abort immediately on the first failing job,
  # and don&#39;t checkout the current directory</span>
  now run --abort --checkout none

<b><u>Usage:</u></b> <b>now</b> &lt;COMMAND&gt;

<b><u>Commands:</u></b>
  <b>init</b>  Initialize a basic workflow
  <b>run</b>   Run one or more jobs
  <b>help</b>  Print this message or the help of the given subcommand(s)

<b><u>Options:</u></b>
  <b>-h</b>, <b>--help</b>
          Print help (see a summary with &#39;-h&#39;)

  <b>-V</b>, <b>--version</b>
          Print version
</pre>

## now init

<pre class="terminal">
Initialize a basic workflow

<b><u>Usage:</u></b> <b>now init</b> [WORKFLOW]

<b><u>Arguments:</u></b>
  [WORKFLOW]  Path to the workflow

<b><u>Options:</u></b>
  <b>-h</b>, <b>--help</b>  Print help
</pre>

## now run

<pre class="terminal">
Run one or more jobs

<b><u>Usage:</u></b> <b>now run</b> [OPTIONS] [JOB]...

<b><u>Arguments:</u></b>
  [JOB]...
          Jobs to target in this run.
          
          If unspecified, the default jobs of the workflow are run.
          
          Cannot be used together with the `--all-jobs` option.

<b><u>Options:</u></b>
  <b>-w</b>, <b>--workflow</b> &lt;FILE&gt;
          Path to the workflow.
          
          Cannot be used together with the `--flake` option.

  <b>-f</b>, <b>--flake</b> &lt;FLAKE[#ATTR]&gt;
          Path to the flake and an optional attribute (defaults to the `now` output).
          
          Cannot be used together with the `--workflow` option.

      <b>--all-jobs</b>
          Run all jobs in the workflow.
          
          Cannot be used together with any `[JOB]` arguments.

  <b>-e</b>, <b>--env-file</b> &lt;FILE&gt;
          Optional dotenv file to read environment variables from

      <b>--abort</b>
          Immediately abort on the first job failure

      <b>--timeout</b> &lt;DURATION&gt;
          Timeout for the entire workflow, eg. `1h`

      <b>--eval</b>
          Evaluate but don&#39;t run the workflow

  <b>-c</b>, <b>--cwdir</b> &lt;CWDIR&gt;
          In which directory to run the workflow.
          
          Defaults to the current directory if --workflow is set, and the directory that `now.nix` is in otherwise

      <b>--builders</b> &lt;BUILDERS&gt;
          A semicolon-separated list of build machines. When specified, overrides the remote builders configuration of the host.
          
          Cannot be used together with the `--local-only` option.
          
          For more information on the syntax, see: &lt;https://nix.dev/manual/nix/latest/command-ref/conf-file#conf-builders&gt;

      <b>--cores</b> &lt;CORES&gt;
          How many simultaneous jobs to use for local builds.
          
          Defaults to the number of physical cores in the current machine.
          
          Cannot be used together with the `--remote-only` option.

      <b>--local-only</b>
          When specified, ignores the remote builders configuration of the host, running all jobs in the local builder.
          
          Jobs that cannot run in the local builder will fail.
          
          Cannot be used together with either the `--builders` or `--remote-only` options.

      <b>--remote-only</b>
          When specified, runs all jobs in remote builders, only using the local runner for job orchestration.
          
          Cannot be used together with either the `--cores` or `--local-only` options.

      <b>--skip</b>
          When specified, skips jobs that don&#39;t match any builders or runners and their dependencies, instead of failing

      <b>--tracing</b>
          Whether to emit traces in Duper instead of colored logs.
          
          For more information on Duper: &lt;https://duper.dev.br&gt;

  <b>-h</b>, <b>--help</b>
          Print help (see a summary with &#39;-h&#39;)
</pre>

