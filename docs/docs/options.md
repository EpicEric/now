---
icon: lucide/square-menu
---
# Options reference
!!! note

    This documentation is auto-generated from the workflow definitions.
## Workflow
A workflow is the main definition of your now commands. It allows you to specify multiple scripts (jobs) in a single source of truth via Nix.
### default

Default job(s) to run for this workflow\.



*Type:*
null or string or list of string



*Default:*

```nix
null
```



### jobs



Jobs in the workflow\.
See the [submodule documentation](\#job)\.



*Type:*
attribute set of (null or job submodule)



*Default:*

```nix
{ }
```



### name



Name of the workflow\.



*Type:*
null or string



*Default:*

```nix
null
```



### nixpkgs



Expression that evaluates to nixpkgs\.



*Type:*
path to nixpkgs



*Default:*

```nix
"<nixpkgs>"
```


## Job
### job

A job is a set of tasks built and run on a single local or remote runner,
made from any number of sequential steps\.

When defined via ` runner.matrix `, you can specify several versions of the same job,
which may run concurrently on multiple builders and runners\.



*Type:*
submodule



### job\.checkout



Strategy for checking out the directory that the job runs on\.
Options are:

 - ` "default" `- use the runner’s current directory;
 - ` "clone" ` - always create a fresh copy of the current directory;
 - ` "none" ` - run in an empty directory\.
 - ` "all" ` - same as ` "default" `, but ignored files are also copied
   over to remote builders\.
 - ` "clone-all" ` - same as ` "clone" `, but ignored files are also copied
   over\.



*Type:*
one of “none”, “default”, “clone”, “all”, “clone-all”



*Default:*

```nix
"default"
```



### job\.env



Environment values to make available to steps in this job\.



*Type:*
attribute set of (string, a call to runner\.secret, or a call to runner\.download)



*Default:*

```nix
{ }
```



### job\.name



Name of the job\.



*Type:*
null or string



*Default:*

```nix
null
```



### job\.needs



Jobs that must be completed before running this one\.



*Type:*
null or string or list of string



*Default:*

```nix
null
```



### job\.sandbox



Default sandbox configuration for the steps in this job\.
See [the submodule documentation](\#sandbox)\.



*Type:*
boolean or (submodule)



*Default:*

```nix
{ }
```



### job\.steps



Steps to run in this job\.
See the [submodule documentation](\#step)\.



*Type:*
list of (null or step submodule)



*Default:*

```nix
[ ]
```



### job\.strategy



How multiple jobs in a matrix should coordinate\.



*Type:*
null or (submodule)



*Default:*

```nix
null
```



### job\.strategy\.failFast



Whether a single failing run should cancel the remaining jobs in the matrix\.



*Type:*
boolean



*Default:*

```nix
true
```



### job\.timeout



How long to run this job for before marking as failed, eg\. ` "30m" ` or ` "1h" `\.
By default, jobs can run indefinitely\.

The timer doesn’t take step realizations or teardowns into account\.



*Type:*
null or string



*Default:*

```nix
null
```


## Step
### step

A step is a single, atomic task that’s run as part of a job\.



*Type:*
submodule



### step\.env



Environment values to make available to this step\.



*Type:*
attribute set of (string, a call to runner\.secret, or a call to runner\.download)



*Default:*

```nix
{ }
```



### step\.name



Name of the step\.



*Type:*
null or string



*Default:*

```nix
null
```



### step\.path



Packages added to the PATH of the script\.



*Type:*
list of package



*Default:*

```nix
[ ]
```



### step\.run



Shell script to run on this step\.



*Type:*
string



*Default:*

```nix
""
```



### step\.sandbox



Sandbox configuration for this step\.
See [the submodule documentation](\#sandbox)\.



*Type:*
boolean or (submodule)



*Default:*

```nix
{ }
```



### step\.shell



The shell to use for this step’s scripts\.

By default, ` bash ` will be used\.



*Type:*
null or package



*Default:*

```nix
null
```



### step\.shellArgs



Args passed to the shell used in this step’s scripts\.



*Type:*
null or (list of string)



*Default:*

```nix
null
```



### step\.teardown



Shell script to run when tearing down this step\.

Jobs always run these, after every step concludes, in reverse order\.



*Type:*
null or string



*Default:*

```nix
null
```


## Sandbox
### sandbox

The sandbox module allows you to specify extra restrictions at
a job or step level\.

Any step settings override job settings\. For example, this allows you to configure
sandboxing for all steps in a job with ` sandbox.enable = true; `, then loosen
permissions on individual steps that have to write to the filesystem\.

On Linux, [` bubblewrap `](https://github\.com/containers/bubblewrap) is used;
on macOS, ` sandbox-exec ` is used\.



*Type:*
submodule



### sandbox\.enable



Whether to use a sandbox for the step\.



*Type:*
boolean



*Default:*

```nix
false
```



### sandbox\.networkAccess



Whether the sandboxed step has network access\.



*Type:*
boolean



*Default:*

```nix
false
```



### sandbox\.useHome



Whether the sandboxed step can use the runner user’s HOME directory\.



*Type:*
boolean



*Default:*

```nix
false
```



### sandbox\.writableNixStore



Whether the sandboxed step can write to the Nix store\.



*Type:*
boolean



*Default:*

```nix
false
```



### sandbox\.writablePath



Whether the sandboxed step can write to the checked-out directory\.



*Type:*
boolean



*Default:*

```nix
false
```


