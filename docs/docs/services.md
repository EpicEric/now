---
icon: lucide/circle-pile
---

# now-services

[`now-services`](https://codeberg.org/now-runner/now-services) is a pluggable collection of steps that let you run development services with `now`.

## Installation

=== "tack"

    ```bash
    tack add now-services git+https://codeberg.org/now-runner/now-services.git --fetch
    ```

    ```nix
    # now.nix
    let
      inputs = import ./.tack;
      services = import inputs.now-services;
    in
    {
      jobs.my_job.steps = [
        (services.postgresql { })
      ];
    }
    ```

=== "npins"

    ```bash
    npins add git https://codeberg.org/now-runner/now-services.git
    ```

    ```nix
    # now.nix
    let
      sources = import ./npins;
      services = import sources.now-services;
    in
    {
      jobs.my_job.steps = [
        (services.postgresql { })
      ];
    }
    ```

=== "Nix flake"

    ```nix
    # flake.nix
    {
      inputs = {
        # ...
        now-services.url = "git+https://codeberg.org/now-runner/now-services.git";
      };

      outputs =
        {
          now-services,
          ...
        }@inputs:
        {
          now.jobs.my_job.steps = [
            (now-services.postgresql { })
          ];
        };
    }
    ```

## Available services

!!! note

    This documentation is auto-generated.

### garage

Run [Garage](https://garagehq.deuxfleurs.fr/), an S3-compatible object store.


Available options:

#### garage.args

Command-line arguments passed to Garage.

_Type:_ `listOf<string>`

_Default:_

```nix
[ ]
```



#### garage.env

`now` environment for this step.

_Type:_ `attrs`

_Default:_

```nix
{ }
```



#### garage.package

The Garage package to use.

_Type:_ `derivation`





### orchestrate

Orchestrate multiple `now` jobs, allowing you to run several services at once.


Available options:

#### orchestrate.env

`now` environment for this step.

_Type:_ `attrs`

_Default:_

```nix
{ }
```



#### orchestrate.jobs

List of `now` job IDs to run concurrently.

_Type:_ `listOf<string>`




#### orchestrate.nowArgs

List of common arguments to pass to each invocation of `now run`.

_Type:_ `listOf<string>`

_Default:_

```nix
[ ]
```



#### orchestrate.package

`now` package to use.

By default, `now` in your PATH is used.


_Type:_ `nullOr<derivation>`




#### orchestrate.strategy

How to handle any failing job.

_Type:_ `strategy`

_Default:_

```nix
"terminate"
```




### postgresql

Run [PostgreSQL](https://www.postgresql.org/), a relational database.


Available options:

#### postgresql.env

`now` environment for this step.

_Type:_ `attrs`

_Default:_

```nix
{ }
```



#### postgresql.package

The PostgreSQL package to use.

_Type:_ `derivation`




#### postgresql.unixSocket

Where to bind the Unix socket for PostgreSQL.

If unspecified, a random directory will be used.


_Type:_ `string`





### redis

Run [Redis](https://redis.io/), an in-memory key-value database, or a derivative.


Available options:

#### redis.cliBinary

Name of the Redis client binary (for healthcheck).

If unspecified, it will be inferred from the package.


_Type:_ `string`




#### redis.env

`now` environment for this step.

_Type:_ `attrs`

_Default:_

```nix
{ }
```



#### redis.package

The Redis package to use.

_Type:_ `derivation`




#### redis.serverBinary

Name of the Redis server binary.

If unspecified, it will be inferred from the package.


_Type:_ `string`
