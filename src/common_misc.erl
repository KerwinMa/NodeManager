%%%-------------------------------------------------------------------
%%% @author
%%% @copyright (C) 2014, <COMPANY>
%%% @doc commmon tool misc
%%%
%%% @end
%%% Created : 27. 二月 2014 下午3:43
%%%-------------------------------------------------------------------
-module(common_misc).

%% API
-export([
    i/0
]).
-export([
    now/0,
    get_connect_center/0,
    get_server_cookie/0,
    get_line_server_key/0,
    get_agent_server_key/0,

    get_server_type/0
]).
-export([
    start_applications/1,
    stop_applications/1
]).

-include("common.hrl").

%% @doc seconds
now() ->
    {A, B, _} = os:timestamp(),
    A * 1000000 + B.

%% @doc 得到中央机的接点信息 @todo 改成配置
%% {NodeKey,NodeName,NodeCookie}
get_connect_center() ->
    {?CENTER_KEYS,'center@127.0.0.1','live_a_better_life!'}.

%% @todo
get_line_server_key() ->
    1.
%% @todo 把每个的cookie都设置为不一样的，才最安全
get_server_cookie() ->
    'live_a_better_life!'.

get_agent_server_key() ->
    1000.

start_applications(Apps) ->
    lists:foldl(fun (App, Acc) ->
        case application:start(App) of
            ok -> [App | Acc];
            {error, {already_started, _}} -> Acc;
            {error, Reason} ->
                lists:foreach(fun application:stop/1, Acc),
                throw({error, {cannot_start_application, App, Reason}})
        end
    end, [], Apps),
    ok.

stop_applications(Apps) ->
    lists:foldl(fun (App, Acc) ->
        case application:stop(App) of
            ok -> [App | Acc];
            {error, {not_started, _}} -> Acc;
            {error, Reason} ->
                lists:foreach(fun application:start/1, Acc),
                throw({error, {cannot_stop_application, App, Reason}})
        end
    end, [], Apps),
    ok.

%% todo 得到服务器的类型
get_server_type() ->
    center.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% for test
i() ->
    case whereis(center_server) of
        undefined -> ok;
        _PID1 ->
            LineInfo1 =  gen_server:call(center_server,{func,fun() -> data_manager:get_center_line_state() end}),
            AgentInfo1 =  gen_server:call(center_server,{func,fun() -> data_manager:get_center_agent_state() end}),
            ?ERROR_MSG("center_server:LineInfo:~p~nAgentInfo:~p:~n",[LineInfo1,AgentInfo1])
    end,
    case whereis(line_server) of
        undefined -> ok;
        _PID2 ->
            LineInfo2 =  gen_server:call(line_server,{func,fun() -> data_manager:get_line_center_state() end}),
            AgentInfo2 =  gen_server:call(line_server,{func,fun() -> data_manager:get_line_agents() end}),
            ?ERROR_MSG("line_server:CenterInfo:~p~nAgentInfo:~p:~n",[LineInfo2,AgentInfo2])
    end,
    case whereis(agent_server) of
        undefined -> ok;
        _PID3 ->
            LineInfo3 =  gen_server:call(agent_server,{func,fun() -> data_manager:get_agent_center_state() end}),
            AgentInfo3 =  gen_server:call(agent_server,{func,fun() -> data_manager:get_agent_lines() end}),
            ?ERROR_MSG("agent_server:CenterInfo:~p~nLineInfo:~p:~n",[LineInfo3,AgentInfo3])
    end.



