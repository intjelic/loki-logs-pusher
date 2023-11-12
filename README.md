# Logs pusher to Loki

A simple logs pusher to Loki for your Erlang logger handlers.

## Getting started.

Logs need to be pushed in batches by making a HTTP POST requests to
Loki. This project implements a logs pusher that accumulates logs and sends
them to Loki on a regular interval. It's also tolerant to disconnection (and is
able to reconnect) and uses a journal on disk to write accumulated logs to, so
it's able to resume in case of crashes and logs are not lost. The logs pusher
is then provided as an application.

```erlang
{ok, Pid} = loki_logs_pusher:start_link("127.0.0.1", 3100, "/tmp/logs.journal").
Stream = #{
    foo => bar,
    bar => quz
}.
Values = [
    {os:system_time(nanosecond), "Hello world!"}
].
loki_logs_pusher:push_logs(Pid, Stream, Values).
```

The previous snippet shows how to start a Loki logs pusher and schedule the
sending of some logs. See the `loki_logs_pusher.erl` file for more
information.

## Project dependency

Both the Rebar3 and Erlang.mk build system are supported.

With the **Rebar3** build system, add the following to the `rebar.config` file
of your project.

```
{deps, [
  {loki_logs_pusher, {git, "https://code.evalarm.de/evalarm/loki_logs_pusher.git", {tag, "master"}}}
]}.
```

If you happen to use the **Erlang.mk** build system, then add the following to
your Makefile.

```
BUILD_DEPS = loki_logs_pusher
dep_loki_logs_pusher = git https://code.evalarm.de/evalarm/loki_logs_pusher.git master
```

Note that in practice, you want to replace the branch "master" with a specific
"tag" to avoid breaking your project if incompatible changes are made.
