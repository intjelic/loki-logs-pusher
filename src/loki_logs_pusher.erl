%%
%% Copyright (c) 2023 - GroupKom GmbH
%%
%% Unauthorized copying of this file, via any medium is strictly prohibited.
%% The source code is proprietary and confidential.
%%
%% Written by Jonathan De Wachter <dewachter.jonathan@gmail.com>
%%
-module(loki_logs_pusher).
-behavior(gen_server).

-export_type([stream/0]).
-export_type([value/0]).
-export_type([logs/0]).

-export([start_link/3]).
-export([stop/1]).

-export([push_logs/3]).

-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_continue/2]).
-export([handle_info/2]).
-export([terminate/2]).

%%
%% Logs pusher to Loki.
%%
%% This module implements a simple logs pusher to Loki to be used in a logger
%% handler. Logs need to be pushed in batches by making a HTTP POST requests to
%% Loki, so the pusher accumulates logs and sends them at regular intervals.
%%
%% Loki does not have to be up when the pusher starts and the pusher is
%% tolerant to disconnections; the logs will be sent as soon as the connection
%% is established (or re-established in case of a disconnection). Because logs
%% are accumulated in memory and would be lost if the application crashes, the
%% pusher must be configured with a journal to write the logs on disk so
%% they can be sent when the application is restarted.
%%
%% Each log is a tuple of a timestamp in nanoseconds and a text line, which is
%% identified by a set of labels.
%%
%% To start a logs pusher, use the start_link/3 function which takes the Loki
%% endpoint (host + port) and the path of the journal to use. To push logs, use
%% the push_logs/3 function. To stop the pusher, use the stop/1 function.
%%
%% XXX: The journal is not implemented.
%% XXX: The implementation is dumb, it just periodically a batch of logs to
%%      Loki (if there are any pending logs) and does not take into account the
%%      possible burst of logs. For instance, when the connection is back up
%%      it could increase the speed at which logs are sent to Loki without
%%      blocking the rest of the logs. Or when the pending logs reaches a
%%      certain size, it can proactively send the logs and not wait for the
%%      next interval.
%% XXX: Functions to adjust push interval, batch size, etc. could be
%%      implemented.
%% XXX: Functions to send logs right away, without queuing logs up, could be
%%      implemented.
%% XXX: Function like flush/0 could be implemented.
%% XXX: Logs should be accumulated in a queue for FIFO behavior.
%% XXX: Batch size should be implemented.
%%
-define(PUSH_INTERVAL, 2000).
-define(SEND_TIMEOUT, 2500).
-define(CONNECTION_RETRY, 5000).

-type stream() :: #{string() | atom() => string() | atom()}.
-type value() :: {pos_integer(), string()}.
-type logs() :: {stream(), [value()]}.

-record(state, {
    connection :: pid(),
    logs = #{} :: #{
        stream() => [value()]
    },
    timer :: pos_integer(),
    journal :: file:name()
}).

%%
%% Start a Loki logs pusher.
%%
%% This function starts a Loki logs pusher. It takes the endpoint of Loki
%% (host + port) and the path of the journal (not implemented yet).
%%
-spec start_link(
    inet:hostname() | inet:ip_address(),
    inet:port_number(),
    file:name()
) -> {ok, pid()}.
start_link(Host, Port, Journal) ->
    gen_server:start_link(?MODULE, [Host, Port, Journal], []).

%%
%% Stop a Loki logs pusher.
%%
%% This function stops a Loki logs pusher.
%%
-spec stop(pid()) -> ok.
stop(Pid) ->
    ok = gen_server:stop(Pid),
    ok.

%%
%% Push logs to Loki.
%%
%% This function adds the logs to the queue of logs to be sent to Loki.
%%
-spec push_logs(pid(), stream(), [value()]) -> ok.
push_logs(Pid, Stream, Values) ->
    gen_server:cast(Pid, {push_logs, Stream, Values}),
    ok.

init([Host, Port, Journal]) ->
    {ok, Connection} = gun:open(Host, Port, #{
        protocols => [http],
        retry_timeout => ?CONNECTION_RETRY
    }),
    {ok, Timer} = timer:send_interval(?PUSH_INTERVAL, self(), send_logs),

    {ok, #state{
        connection = Connection,
        timer = Timer,
        journal = Journal
    }}.

handle_call(stop, _From, State) ->
    {stop, normal, State}.

handle_cast(
    {push_logs, Stream, Values},
    #state{logs = Logs} = State
) ->
    UpdatedLogs = maps:put(Stream, maps:get(Stream, Logs, []) ++ Values, Logs),
    {noreply, State#state{logs = UpdatedLogs}}.

handle_continue(
    send_logs,
    #state{logs = Logs} = State
) when map_size(Logs) == 0 ->
    % Do nothing if there's no log.
    {noreply, State};

handle_continue(
    send_logs,
    #state{
        connection = Connection,
        logs = Logs
    } = State
) ->
    Data = #{
        streams => lists:map(fun({Stream, Values}) ->
            #{
                stream => Stream,
                values => lists:map(fun({Timestamp, Text}) ->
                    [integer_to_binary(Timestamp), list_to_binary(Text)]
                end, Values)
            }
        end, maps:to_list(Logs))
    },
    Headers = #{
        <<"Content-Type">> => <<"application/json">>
    },
    Stream = gun:post(
        Connection,
        "/loki/api/v1/push",
        Headers,
        jsx:encode(Data)
    ),
    case gun:await(Connection, Stream) of
        {response, fin, 204, _} ->
            {noreply, State#state{logs = #{}}};
        _ ->
            {noreply, State}
    end.

handle_info(
    {gun_up, Connection, http},
    #state{connection = Connection} = State
) ->
    {noreply, State};

handle_info(
    {gun_down, Connection, http, _Reason, _KilledStreams},
    #state{connection = Connection} = State
) ->
    {noreply, State};

handle_info(send_logs, State) ->
    {noreply, State, {continue, send_logs}}.

terminate(_Reason, _State) ->
    ok.
