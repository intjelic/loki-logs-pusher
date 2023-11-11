%%
%% Copyright (c) 2023 - GroupKom GmbH
%%
%% Unauthorized copying of this file, via any medium is strictly prohibited.
%% The source code is proprietary and confidential.
%%
%% Written by Jonathan De Wachter <dewachter.jonathan@gmail.com>
%%
-module(loki_logs_pusher_test).
-include_lib("eunit/include/eunit.hrl").

-define(PORT, 3100).

start_loki() ->
    Dispatch = cowboy_router:compile([
        {'_', [{"/loki/api/v1/push", loki_logs_handler, []}]}
    ]),

    {ok, _Pid} = cowboy:start_clear(
        loki_listener,
        [{port, ?PORT}],
        #{env => #{dispatch => Dispatch}}
    ),

    ok.

expect_logs(Timeout) ->
    receive
        {logs, Logs} ->
            Logs
    after Timeout ->
        throw(expected_logs)
    end.

expect_no_logs(Timeout) ->
    receive
        _ ->
            throw(expected_no_logs)
    after Timeout ->
        ok
    end.

loki_logs_pusher_test_() ->
    {timeout, 15, fun() ->
        application:ensure_all_started(gun),
        application:ensure_all_started(cowboy),

        meck:new(loki_logs_handler, [non_strict]),

        Parent = self(),
        meck:expect(loki_logs_handler, init, fun(Request, State) ->
            {ok, Body, UpdatedRequest} = cowboy_req:read_body(Request),
            Parent ! {logs, jsx:decode(Body)},
            Response = cowboy_req:reply(204, UpdatedRequest),
            {ok, Response, State}
        end),

        {ok, Pid} = loki_logs_pusher:start_link(
            "localhost",
            3100,
            "/tmp/logs.journal"
        ),

        Stream1 = #{
            foo => bar,
            bar => quz
        },
        Stream2 = #{
            quz => foo
        },

        Now1 = os:system_time(nanosecond),
        loki_logs_pusher:push_logs(Pid, Stream1, [
            {Now1 + 100, "foo"},
            {Now1 + 200, "bar"}
        ]),
        loki_logs_pusher:push_logs(Pid, Stream1, [
            {Now1 + 300, "quz"}
        ]),
        loki_logs_pusher:push_logs(Pid, Stream2, [
            {Now1 + 400, "yolo"},
            {Now1 + 500, "oloy"}
        ]),

        expect_no_logs(3000),

        start_loki(),

        Logs1 = expect_logs(6000),
        true = lists:member(#{
            <<"stream">> => #{
                <<"bar">> => <<"quz">>,
                <<"foo">> => <<"bar">>
            },
            <<"values">> => [
                [integer_to_binary(Now1 + 100), <<"foo">>],
                [integer_to_binary(Now1 + 200), <<"bar">>],
                [integer_to_binary(Now1 + 300), <<"quz">>]
            ]
        }, maps:get(<<"streams">>, Logs1)),
        true = lists:member(#{
            <<"stream">> => #{
                <<"quz">> => <<"foo">>
            },
            <<"values">> => [
                [integer_to_binary(Now1 + 400), <<"yolo">>],
                [integer_to_binary(Now1 + 500), <<"oloy">>]
            ]
        }, maps:get(<<"streams">>, Logs1)),

        Now2 = os:system_time(nanosecond),

        loki_logs_pusher:push_logs(Pid, Stream1, [
            {Now2 + 100, "foo"},
            {Now2 + 200, "bar"}
        ]),
        loki_logs_pusher:push_logs(Pid, Stream2, [
            {Now2 + 300, "quz"}
        ]),

        Logs2 = expect_logs(3000),
        true = lists:member(#{
            <<"stream">> => #{
                <<"bar">> => <<"quz">>,
                <<"foo">> => <<"bar">>
            },
            <<"values">> => [
                [integer_to_binary(Now2 + 100), <<"foo">>],
                [integer_to_binary(Now2 + 200), <<"bar">>]
            ]
        }, maps:get(<<"streams">>, Logs2)),
        true = lists:member(#{
            <<"stream">> => #{
                <<"quz">> => <<"foo">>
            },
            <<"values">> => [
                [integer_to_binary(Now2 + 300), <<"quz">>]
            ]
        }, maps:get(<<"streams">>, Logs2)),

        ok = loki_logs_pusher:stop(Pid),

        meck:unload(loki_logs_handler),

        ok
    end}.
