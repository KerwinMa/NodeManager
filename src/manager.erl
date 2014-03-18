%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(manager).

-behaviour(application).

%% Application callbacks
-export([
    start/0,
    stop/0,
    start/2,
    stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================
-define(APPS, [sasl, asn1, manager]).

start() ->
    try
        ok = common_misc:start_applications(?APPS)
    after
        timer:sleep(100)
    end.

stop() ->
    ok = common_misc:stop_applications(lists:reverse(?APPS)).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: term()) ->
    {ok, pid()} |
    {ok, pid(), State :: term()} |
    {error, Reason :: term()}).
start(_StartType, _StartArgs) ->
    {ok, Pid} = manager_sup:start_link(),
    case common_misc:get_server_type() of
        agent -> agent_server:start();
        line -> line_server:start();
        center -> center_server:start()
    end,
    {ok,Pid}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
    ok.
%%%===================================================================
%%% Internal functions
%%%===================================================================
