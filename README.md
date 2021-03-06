# eredis_cluster (Nordix fork)

## Description

eredis_cluster is a wrapper for eredis to support cluster mode of Redis 3.0.0+

Improvements compared to `adrienmo/eredis_cluster`:

* Support of TLS introduced in Redis 6
* Uses Nordix/eredis
* Many Dialyzer corrections
* Elvis code formatting
* Containerized testing
* Added APIs:
  - `connect/2`             - Connect to init nodes, with options
  - `qa2/1`                 - query all nodes with re-attempts, returns [{Node, Result},..]
  - `q_noreply/1`           - query a single Redis instance but wont wait for its result
  - `load_script/1`         - pre-load script to all Redis instances
  - `scan/4`                - Perform a scan command on given Redis instance
  - `disconnect/1`          - disconnect from given Redis instances
  - `get_pool_by_command/1` - get which Redis pool that handles a given command
  - `get_pool_by_key/1`     - get which Redis pool that handles a given key
  - `get_cluster_nodes/0`   - get cluster nodes information list (CLUSTER NODES)
  - `get_cluster_slots/0`   - get cluster slots information (CLUSTER SLOTS)
* Changed behaviour:
  - `qa/1`                  - query all nodes, now with re-attempts
  - `get_cluster_slots/2`   - Gives descriptive errors when failing

## TODO

- Correct last Dialyzer warnings
- Improve test coverage
- `get_cluster_slots/2`, throw a reply?, improve tests
- Improve test suite to demonstrate the case where Redis cluster is crashing,
  resharding, recovering...

## Compilation and tests

The directory contains a Makefile that uses rebar3.

Setup a Redis cluster and start the tests using following commands:

```bash
make
make start  # Start a local Redis cluster
make test   # Run tests towards the cluster
make stop   # Teardown the Redis cluster
```

## Configuration

To configure the Redis cluster, you can use an application variable (probably in
your app.config):

    {eredis_cluster,
        [
            {init_nodes,[
                {"127.0.0.1", 30001},
                {"127.0.0.1", 30002}
            ]},
            {pool_size, 5},
            {pool_max_overflow, 10},

            {password, "redis_pw"},
            {socket_options, [{send_timeout, 6000}, ...]},
            {tls, [{cacertfile, "ca.crt"}, ...]}
        ]
    }

You don't need to specify all nodes of your configuration as eredis_cluster will
retrieve them through the command `CLUSTER SLOTS` at runtime.

### Configuration description

* `init_nodes`: List of Redis instances to fetch cluster information from. Default: `[]`
* `pool_size`: Number of connected clients to each Redis instance. Default: `10`
* `pool_max_overflow`: Max number of extra clients that can be started when the pool is exhausted. Default: `0`
* `password`: Password to use for a Redis cluster configured with `requirepass`. Default: `""` (i.e. AUTH not sent)
* `socket_options`: Extra socket [options](http://erlang.org/doc/man/gen_tcp.html#type-option). Enables selecting host interface or perf. tuning. Default: `[]`
* `tls`: Enable TLS/SSL and use specified [TLSOptions](https://erlang.org/doc/man/ssl.html#type-client_option). Default: TLS not enabled.

### Configuring via API

An alternative is to set configurations programmatically via set_env() and `eredis_cluster:connect/1`.

```erlang
application:set_env(eredis_cluster, pool_size, 5),
application:set_env(eredis_cluster, pool_max_overflow, 10),
application:set_env(eredis_cluster, password, "redis_pw"),
application:set_env(eredis_cluster, socket_options, [{send_timeout, 6000}]),
application:set_env(eredis_cluster, tls, [{cacertfile, "ca.crt"},
                                          {certfile, "client.crt"},
                                          {keyfile, "client.key"}]),

%% Set initial nodes and perform a controlled connect
eredis_cluster:connect([{"127.0.0.1", 30001},
                        {"127.0.0.1", 30002}]).
```

#### Alternative: set overriding options when calling connect

It is also possible to give options while doing a connect using `eredis_cluster:connect/2` instead.
The given options will precede options set via application configuration,
i.e will be prepended to the property list.

```erlang
Options = [{tls, [{cacertfile, "ca.crt"},
                  {certfile, "client.crt"},
                  {keyfile, "client.key"}]}],
eredis_cluster:connect([{"127.0.0.1", 30001},
                        {"127.0.0.1", 30002}], Options).
```

## Usage

```erlang
%% Start the application
eredis_cluster:start().

%% Simple command
eredis_cluster:q(["GET","abc"]).

%% Pipeline
eredis_cluster:qp([["LPUSH", "a", "a"], ["LPUSH", "a", "b"], ["LPUSH", "a", "c"]]).

%% Pipeline in multiple node (keys are sorted by node, a pipeline request is
%% made on each node, then the result is aggregated and returned. The response
%% keep the command order
eredis_cluster:qmn([["GET", "a"], ["GET", "b"], ["GET", "c"]]).

%% Transaction
eredis_cluster:transaction([["LPUSH", "a", "a"], ["LPUSH", "a", "b"], ["LPUSH", "a", "c"]]).

%% Transaction Function
Function = fun(Worker) ->
    eredis_cluster:qw(Worker, ["WATCH", "abc"]),
    {ok, Var} = eredis_cluster:qw(Worker, ["GET", "abc"]),

    %% Do something with Var %%
    Var2 = binary_to_integer(Var) + 1,

    {ok, Result} = eredis_cluster:qw(Worker,[["MULTI"], ["SET", "abc", Var2], ["EXEC"]]),
    lists:last(Result)
end,
eredis_cluster:transaction(Function, "abc").

%% Optimistic Locking Transaction
Function = fun(GetResult) ->
    {ok, Var} = GetResult,
    Var2 = binary_to_integer(Var) + 1,
    {[["SET", Key, Var2]], Var2}
end,
Result = optimistic_locking_transaction(Key, ["GET", Key], Function),
{ok, {TransactionResult, CustomVar}} = Result

%% Atomic Key update
Fun = fun(Var) -> binary_to_integer(Var) + 1 end,
eredis_cluster:update_key("abc", Fun).

%% Atomic Field update
Fun = fun(Var) -> binary_to_integer(Var) + 1 end,
eredis_cluster:update_hash_field("abc", "efg", Fun).

%% Eval script, both script and hash are necessary to execute the command,
%% the script hash should be precomputed at compile time otherwise, it will
%% execute it at each request. Could be solved by using a macro though.
Script = "return redis.call('set', KEYS[1], ARGV[1]);",
ScriptHash = "4bf5e0d8612687699341ea7db19218e83f77b7cf",
eredis_cluster:eval(Script, ScriptHash, ["abc"], ["123"]).

%% Flush DB
eredis_cluster:flushdb().

%% Query on all cluster server
eredis_cluster:qa(["FLUSHDB"]).

%% Execute a query on the server containing the key "TEST"
eredis_cluster:qk(["FLUSHDB"], "TEST").
```

## Troubleshooting

Following Redis-log indicates that Redis accepts TLS, but the client is not configured for TLS.

```
# Error accepting a client connection: error:1408F10B:SSL routines:ssl3_get_record:wrong version number (conn: fd=12)
```

Debug logging for TLS connections can be enabled in eredis_cluster by the connect option: `{log_level, debug}`
