%%%-------------------------------------------------------------------
%%% @doc 分线机line :从agent上来的进程可以在这里得到相应的服务
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(line_server).

-behaviour(gen_server).

%% API
-export([
    start/0,
    start_link/0]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-include("common.hrl").
-define(SERVER, ?MODULE).

%%init 200ms后检查连接center_server时间
-define(LINE_INIT_CONNECT_MS,200).

-record(state,{}).

%%%===================================================================
%%% API
%%%===================================================================

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
    data_manager:line_new(),
    erlang:send_after(?LINE_INIT_CONNECT_MS,self(),loop_second),
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
        ?ERROR_MSG("line_server:recv_info:~p:~p~n",[time(),Info]),
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
        true -> {error, time_out};
        false -> F()
    end;
do_handle_call(Request) ->
    ?ERROR_MSG("center_server unknow call ~p", [Request]),
    ok.

do_handle_info({func, F}) ->
    F();

do_handle_info({func, Time, F}) when is_function(F) ->
    case common_misc:now() - Time > ?CALL_TIMETOUT of
        true -> {error,time_out};
        false -> F()
    end;
do_handle_info({nodedown, NodeName}) ->
    do_node_down(NodeName);

do_handle_info(loop_second) ->
    erlang:send_after(?FIVE_LOOP_SECOND,self(),loop_second),
    do_loop_second();

do_handle_info({connect_center_ok, NodeKey, NodeName,NodeCookie,StatePID}) ->
    do_connect_center_ok(NodeKey, NodeName,NodeCookie,StatePID);
do_handle_info({line_reg_center,NodeKey, NodeName,NodeCookie,StatePID}) ->
    do_line_reg_center(NodeKey, NodeName,NodeCookie,StatePID);

do_handle_info({center_agent_state,CenterServices,AllAgentList}) ->
    do_recv_center_agent_state(CenterServices,AllAgentList);

do_handle_info(Info) ->
    ?ERROR_MSG("line_server unknow info ~p", [Info]).

do_node_down(NodeName) ->
    #node_connect_state{node = CenterNodeName} = data_manager:get_line_center_state(),
    case NodeName =:= CenterNodeName of
        true -> data_manager:set_line_center_state(#node_connect_state{});
        false -> ok
    end,
    AllAgentList = data_manager:get_line_agents(),
    data_manager:set_line_agents(lists:keydelete(NodeName,#node_connect_state.node,AllAgentList)),
    ok.

do_loop_second() ->
    case data_manager:get_line_center_state() of
        #node_connect_state{state_pid=PID,node=CenterNodeName} when erlang:is_pid(PID)  ->
            case common_misc:now() rem 15 < 5 of %%15s检查下
                true -> do_check_center_state(CenterNodeName);
                _ -> ignore
            end;
        _ ->%%未连上中央控制
            {NodeKey,NodeName,NodeCookie} = common_misc:get_connect_center(),
            do_connect_center(NodeKey,NodeName,NodeCookie,undefined,?NODE_DISCONN)
    end.

%% 节点已链接，可应用
do_connect_center(_NodeKey,_NodeName,_NodeCookie,_StatePID,ConnStatus)when ConnStatus >= ?NODE_USABLE ->
    ignore;
%% 节点未接或已接但是不可应用
do_connect_center(NodeKey,NodeName,NodeCookie,StatePID,_ConnStatus) ->
    SelfPID = erlang:self(),
    erlang:spawn(fun() -> do_connect_center2(NodeKey, NodeName, NodeCookie,StatePID,SelfPID) end).

do_connect_center2(NodeKey, NodeName, NodeCookie,StatePID, ParentPID) ->
    true = erlang:set_cookie(NodeName, NodeCookie),
    case net_kernel:connect_node(NodeName) of
        true -> erlang:send(ParentPID,{connect_center_ok, NodeKey, NodeName,NodeCookie,StatePID});
        _ -> ignore
    end.

do_connect_center_ok(NodeKey,NodeName,NodeCookie,StatePID) ->
    MyStatePID=self(),
    State = data_manager:get_line_center_state(),
    erlang:send_after(?CONFIRM_OK_TIMES, MyStatePID, {line_reg_center,NodeKey, NodeName,NodeCookie,MyStatePID}),
    data_manager:set_line_center_state(State#node_connect_state{node_key = NodeKey, node = NodeName,cookie = NodeCookie,
    status = ?NODE_ESTABLISH,state_pid = StatePID}).

%% 已连接到中央机节点 确定中央机应用已起来后：PID
do_line_reg_center(_CenterNodeKey, CenterNodeName,_CenterNodeCookie,StatePID) ->
    case rpc:call(CenterNodeName, erlang, whereis, [center_server]) of
        CenterStatePID when erlang:is_pid(CenterStatePID) ->
            ?ERROR_MSG("line_connect_to_center_server ok :~p",[{CenterNodeName}]),
            ThisNodeKey = common_misc:get_line_server_key(),
            NodeCookie = common_misc:get_server_cookie(),
            RegisterMsg={line_reg,ThisNodeKey,node(),NodeCookie,StatePID},
            erlang:send(CenterStatePID,RegisterMsg),
            CNodeState = data_manager:get_line_center_state(),
            data_manager:set_line_center_state(CNodeState#node_connect_state{status = ?NODE_USABLE,state_pid = CenterStatePID});
        _ ->
            ?ERROR_MSG("Error:line_connect_to_center_server:error~p", [CenterNodeName]),
            net_kernel:disconnect(CenterNodeName)
    end.
do_recv_center_agent_state(_CenterServices,NewAgentList) ->
    data_manager:line_update_agents(NewAgentList).
%% todo 把centerserver存好
%%data_manager:set_line_center_state(CenterServices).

%% @todo 检查节点的状态
do_check_center_state(_CenterNodeName) ->
    ok.