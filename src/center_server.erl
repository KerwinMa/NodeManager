%%%-------------------------------------------------------------------
%%% @author
%%% @doc 中央机:负责把agent server与line serverr同步节点状态
%%% @end
%%%-------------------------------------------------------------------
-module(center_server).

-behaviour(gen_server).


%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

%% API
-export([
    start/0,
    start_link/0
]).
-export([
    service_reg/2,
    service_dereg/2
]).

-include("common.hrl").
-define(SERVER, ?MODULE).
%%init后多少ms可以进入秒循环
-define(CNETER_INIT_CONNECT_MS,200).

-define(SIXTY_LOOP_SECOND,6000*10).

-define(ETS_CENTER_DATA,ets_center_data).
-record(state,{}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc 在中央机中注册服务，【用于服务agent上的进程，如agent1,agent2数据要排序则，都在center node
%% 上开个服务进程来做这件事
service_reg(ServiceName,ServicePID) ->
    erlang:send(?MODULE,{service_reg,ServiceName,ServicePID}).
service_dereg(ServiceName,ServicePID) ->
    erlang:send(?MODULE,{service_dereg,ServiceName,ServicePID}).

start() ->
    {ok, PID} = supervisor:start_child(manager_sup, {?MODULE,
        {?MODULE, start_link, []},
        permanent, 30000000, worker, [?MODULE]}),
    PID.

-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    erlang:process_flag(trap_exit, true),
    ets:new(?ETS_CENTER_DATA, [named_table, set, protected,{read_concurrency, true}]),
    erlang:send_after(?CNETER_INIT_CONNECT_MS,self(),loop_second),
    {ok, #state{}}.

-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).

handle_call(Request, _From, State) ->
    Reply = try do_handle_call(Request)
            catch _:Reason ->
                ?ERROR_MSG("Request:~w~n,State=~w~n, Reason: ~w~n, strace:~p", [Request,State, Reason, erlang:get_stacktrace()])
            end,
    {reply, Reply, State}.

-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(Request, State) ->
    ?ERROR_MSG("cneter_server,unknow cast：~w",[Request]),
    {noreply, State}.

-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(Info, State) ->
    try
        ?ERROR_MSG("center_server:recv_info:~p:~p~n",[time(),Info]),
        do_handle_info(Info)
    catch _:Reason ->
        ?ERROR_MSG("Info:~w~n,State=~w~n, Reason: ~w~n, strace:~p", [Info,State, Reason, erlang:get_stacktrace()])
    end,
    {noreply, State}.

-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
do_handle_call({func, F}) ->
    F();
do_handle_call({func, Time, F}) when is_function(F) ->
    case common_misc:now() - Time > ?CALL_TIMETOUT of
        true -> {error,time_out};
        false -> F()
    end;
do_handle_call(Request) ->
    ?ERROR_MSG("center_server unknow call ~p", [Request]),
    ok.

do_handle_info({func, F}) ->
    F();
do_handle_info({func, Time, F}) when is_function(F) ->
    case common_misc:now() - Time > ?CALL_TIMETOUT of
        true -> ok;
        false -> F()
    end;
do_handle_info({nodedown, NodeName}) ->
    do_node_down(NodeName);

do_handle_info(loop_second) ->
    erlang:send_after(?SIXTY_LOOP_SECOND,self(),loop_second),
    do_loop();

do_handle_info({agent_reg,NodeKey,NodeName,NodeStatePID}) ->
    do_agent_reg(NodeKey,NodeName,NodeStatePID);
do_handle_info({line_reg,NodeKey,NodeName,NodeCookie,NodeStatePID}) ->
    do_line_reg(NodeKey,NodeName,NodeCookie,NodeStatePID);

do_handle_info({service_reg,ServiceName,ServicePID}) ->
    do_service_reg(ServiceName,ServicePID);
do_handle_info({service_dereg,ServiceName,ServicePID}) ->
    do_service_dereg(ServiceName,ServicePID);

do_handle_info({line_msg, {Mod, Msg}}) ->
    do_line_msg(Mod, Msg);

do_handle_info(Info) ->
    ?ERROR_MSG("center_server unknow info ~p", [Info]).

%% 监控到节点down了
do_node_down(NodeName) ->
    AllLineList = data_manager:get_center_line_state(),
    data_manager:set_center_line_state(lists:keydelete(NodeName,#node_connect_state.node,AllLineList)),
    AllAgentList = data_manager:get_center_agent_state(),
    data_manager:set_center_agent_state(lists:keydelete(NodeName,#node_connect_state.node,AllAgentList)),
    do_send_all_line_state(),
    do_send_all_agent_state(),
    ok.

%%  @doc 60s同步一次状态
do_loop() ->
    do_send_all_line_state(),
    do_send_all_agent_state(),
    ok.
%% @doc  agent node连接上来center
%% 把 所有lines同步到新的agent node上
do_agent_reg(NodeKey,NodeName,NodeStatePID) ->
    AgentList = data_manager:get_center_agent_state(),
    New = #node_connect_state{node_key = NodeKey,node = NodeName,state_pid = NodeStatePID},
    case lists:keymember(NodeKey,#node_connect_state.node_key,AgentList) of
        false ->  data_manager:set_center_agent_state([New|AgentList]);
        true  -> ignore
    end,
    do_send_all_line_state([New]),
    ok.
%% @doc line node 连接上来center
%% 把所有的agent 同步到新 line node上
do_line_reg(NodeKey,NodeName,NodeCookie,NodeStatePID) ->
    LineList = data_manager:get_center_line_state(),
    New = #node_connect_state{node_key = NodeKey,node = NodeName,state_pid = NodeStatePID,cookie = NodeCookie},
    case lists:keymember(NodeKey,#node_connect_state.node_key,LineList) of
        true ->  ignore;
        false -> data_manager:set_center_line_state([New|LineList])
    end,
    do_send_all_agent_state([#node_connect_state{node_key = NodeKey,node = NodeName,state_pid = NodeStatePID}]),
    ok.
%% @doc 在中央机上注册服务
do_service_reg(ServiceName,ServicePID) ->
    add_center_services(ServiceName,ServicePID).
%% @doc 在中央机上注销服务
do_service_dereg(ServiceName,ServicePID) ->
    del_center_services(ServiceName,ServicePID),
    do_send_all_line_state(),
    do_send_all_agent_state().

%% 把所有分线line机状态同步到每一个代理agent机
do_send_all_line_state() ->
    case data_manager:get_center_agent_state() of
        [] -> ok;
        AllAgentList -> do_send_all_line_state(AllAgentList)
    end.

%% @doc 对指定agentlist同步line状态
do_send_all_line_state(AllAgentList) ->
    AllLineList = data_manager:get_center_line_state(),
    CenterServices = get_center_services(),
    [begin erlang:send(AgentStatePID,{center_line_state,CenterServices,AllLineList})
     end || #node_connect_state{state_pid = AgentStatePID} <- AllAgentList],
    ok.
%% @doc 把所有agent状态同步到每一个line机上
do_send_all_agent_state() ->
    case data_manager:get_center_line_state() of
        [] -> ok;
        AllLineList -> do_send_all_agent_state(AllLineList)
    end.
%% @doc 对指定linelist同步agent状态
do_send_all_agent_state(AllLineList) ->
    AllAgentList = data_manager:get_center_agent_state(),
    CenterServices = get_center_services(),
    [begin erlang:send(AgentStatePID,{center_agent_state,CenterServices,AllAgentList})
     end || #node_connect_state{state_pid = AgentStatePID} <- AllLineList],
    ok.

%% @doc todo
do_line_msg(Mod, Msg) ->
    catch erlang:send(whereis(Mod), Msg).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% dict进程字典相关
get_center_services() ->
    case erlang:get(center_services) of
        [_|_] =List ->List;
        _-> []
    end.

add_center_services(ServiceName,ServicePID) ->
    OldList = get_center_services(),
    case lists:member({ServiceName,ServicePID},OldList) of
        true -> ignore;
        _ -> erlang:put(center_services,[{ServiceName,ServicePID}|OldList])
    end.

del_center_services(ServiceName,_ServicePID) ->
    OldList = get_center_services(),
    case lists:keymember(ServiceName, 1, OldList)of
        true -> erlang:put(center_services,lists:keydelete(ServiceName, 1, OldList));
        _ -> ignore
    end.