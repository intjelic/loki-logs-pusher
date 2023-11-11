PROJECT = loki_logs_pusher
PROJECT_DESCRIPTION = Logs pusher to Loki for your Erlang logger handlers.
PROJECT_VERSION = 0.1.0

DEPS = gun jsx
TEST_DEPS = meck cowboy

dep_cowboy = git https://github.com/ninenines/cowboy.git 2.9.0
dep_gun = git https://github.com/ninenines/gun.git 2.0.0
dep_meck = git https://github.com/eproxus/meck.git 0.9.2
dep_jsx = git https://github.com/talentdeficit/jsx v3.1.0

include erlang.mk
