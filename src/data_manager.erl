%%%-------------------------------------------------------------------
%%% @author
%%% @copyright (C) 2014, <COMPANY>
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(data_manager).

%% API
-export([
    line_new/0,
    agent_new/0,
    agent_update_lines/1,

    get_agent_lines/0,
    set_agent_lines/1,
    add_agent_line/1,

    line_update_agents/1,
    get_line_agents/0,
    set_line_agents/1,
    add_line_agent/1,

    get_agent_center_state/0,
    set_agent_center_state/1,

    set_line_center_state/1,
    get_line_center_state/0,

    get_center_line_state/0,
    set_center_line_state/1,

    get_center_agent_state/0,
    set_center_agent_state/1
]).

-include("common.hrl").
-define(ETS_LINE_DATA,ets_line_data).
-define(ETS_AGENT_DATA,ets_agent_data).

%% @doc 新建分线存储状态结构
line_new() ->
    ets:new(?ETS_LINE_DATA, [named_table, set, protected,{read_concurrency, true}]).

agent_new() ->
    ets:new(?ETS_AGENT_DATA, [named_table, set, protected,{read_concurrency, true}]).

agent_update_lines(AllLineList) ->
    ets:insert(?ETS_AGENT_DATA, {all_line_list,AllLineList}).


get_agent_lines() ->
    case ets:lookup(?ETS_AGENT_DATA,all_line_list) of
        [{all_line_list,List}]  -> List;
        [] ->[]
    end.


set_agent_lines(AllLines) ->
    ets:insert(?ETS_AGENT_DATA,{all_line_list,AllLines}).

add_agent_line(#node_connect_state{node_key = NodeKey} = AddNode) ->
    AllAgentLines = get_agent_lines(),
    case lists:keytake(NodeKey,#node_connect_state.node_key,AllAgentLines) of
        false -> set_agent_lines([AddNode|AllAgentLines]);
        {value,_T,Left} -> set_agent_lines([AddNode|Left])
    end.

line_update_agents(AllAgentList) ->
    ets:insert(?ETS_LINE_DATA, {all_agent_list,AllAgentList}).

get_line_agents() ->
    case ets:lookup(?ETS_LINE_DATA,all_agent_list) of
        [{_,List}] ->List;
        [] -> []
    end.

set_line_agents(AllLines) ->
    ets:insert(?ETS_LINE_DATA,{all_agent_list,AllLines}).

add_line_agent(#node_connect_state{node_key = NodeKey} = AddNode) ->
    AllAgentLines = get_agent_lines(),
    case lists:keytake(NodeKey,#node_connect_state.node_key,AllAgentLines) of
        false -> set_line_agents([AddNode|AllAgentLines]);
        {value,_T,Left} -> set_line_agents([AddNode|Left])
    end.

%% @doc 在agent上center node的状态
get_agent_center_state() ->
    erlang:get(agent_center_state).
set_agent_center_state(Info) ->
    erlang:put(agent_center_state,Info).

%% @doc 在line上center node的状态
get_line_center_state() ->
    case erlang:get(line_center_state) of
        undefined -> #node_connect_state{};
        T -> T
    end.
set_line_center_state(Info) ->
    erlang:put(line_center_state,Info).

%% @doc 在center 上line的node list状态
get_center_line_state() ->
    case erlang:get(center_line_state) of
        undefined -> [];
        List -> List
    end.

set_center_line_state(List) ->
    erlang:put(center_line_state,List).

%% @doc 在center上的agent的node list状态
get_center_agent_state() ->
    case erlang:get(center_agent_state) of
        undefined -> [];
        List -> List
    end.
set_center_agent_state(List)when is_list(List) ->
    erlang:put(center_agent_state,List).
