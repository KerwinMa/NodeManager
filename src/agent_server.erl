%%%-------------------------------------------------------------------
%%% @doc 代理机agent，实际就是agent上的进程到line上运行
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(agent_server).

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
-define(AGENT_INIT_CONNECT_MS,200).

-record(state, {}).

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
    data_manager:agent_new(),
    erlang:send_after(?AGENT_INIT_CONNECT_MS,self(),loop_second),
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
handle_cast(_Request, State) ->
    {noreply, State}.

-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(Info, State) ->
    try
        ?ERROR_MSG("agent_server:recv_info:~p:~p~n",[ time(),Info]),
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
do_handle_call({func, Time, F}) when erlang:is_function(F) ->
    case common_misc:now() - Time > ?CALL_TIMETOUT of
        true -> {error, call_timeout};
        false -> F()
    end;
do_handle_call(Request) ->
    ?ERROR_MSG("mod_cross_agent_state unknow call ~p", [Request]).

do_handle_info({func, F}) ->
    F();
do_handle_info({func, Time, F}) when erlang:is_function(F) ->
    case common_tool:now() - Time > ?CALL_TIMETOUT of
        true -> {error, info_timeout};
        false -> F()
    end;

do_handle_info({nodedown, NodeName}) ->
    do_node_down(NodeName);
do_handle_info(loop_second) ->
    erlang:send_after(?FIVE_LOOP_SECOND,self(),loop_second),
    do_loop_second();
do_handle_info({connect_center_ok, NodeKey, NodeName,NodeCookie,StatePID}) ->
    do_connect_center_ok(NodeKey, NodeName,NodeCookie,StatePID);
do_handle_info({agent_reg_center,NodeKey, NodeName,NodeCookie,StatePID}) ->
    do_agent_reg_center(NodeKey, NodeName,NodeCookie,StatePID);

do_handle_info({center_line_state,CenterServices,NodeStates}) ->
    do_recv_center_line_state(CenterServices,NodeStates);
do_handle_info({connect_line_ok, NodeKey, NodeName,NodeCookie,StatePID}) ->
    do_connect_line_ok(NodeKey,NodeName,NodeCookie,StatePID);

do_handle_info(Info) ->
    ?ERROR_MSG("mod_cross_agent_state unknow info ~p", [Info]).

do_node_down(NodeName) ->
    #node_connect_state{node = CenterNodeName} = data_manager:get_agent_center_state(),
    case NodeName =:= CenterNodeName of
        true -> data_manager:set_agent_center_state(#node_connect_state{});
        false -> ok
    end,
    AllAgentList = data_manager:get_agent_lines(),
    data_manager:set_agent_lines(lists:keydelete(NodeName,#node_connect_state.node,AllAgentList)),
    ok.
do_loop_second() ->
    case data_manager:get_agent_center_state() of%%已经连上中央控制
        #node_connect_state{state_pid=PID,node=CenterNodeName} when erlang:is_pid(PID)  ->
            case common_misc:now() rem 15 < 5 of
                true -> do_check_center_state(CenterNodeName);
                _ -> ignore
            end;
        _ ->%%未连上中央控制
            {NodeKey,NodeName,NodeCookie} = common_misc:get_connect_center(),
            do_connect_center(NodeKey,NodeName,NodeCookie,undefined,?NODE_DISCONN)
    end.
%%节点已链接，可应用
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
    erlang:send_after(?CONFIRM_OK_TIMES, MyStatePID, {agent_reg_center,NodeKey, NodeName,NodeCookie,MyStatePID}),
    NewState = #node_connect_state{node_key = NodeKey, node = NodeName,cookie = NodeCookie,status = ?NODE_ESTABLISH,state_pid = StatePID},
    data_manager:set_agent_center_state(NewState).

do_agent_reg_center(_CenterNodeKey, CenterNodeName,_CenterNodeCookie,StatePID) ->
    case rpc:call(CenterNodeName, erlang, whereis, [center_server]) of
        CenterStatePID when erlang:is_pid(CenterStatePID) ->
            ?ERROR_MSG("agent_connect_to_center: :~w",[{CenterNodeName}]),
            #node_connect_state{} = CNodeState = data_manager:get_agent_center_state(),
            data_manager:set_agent_center_state(CNodeState#node_connect_state{state_pid=CenterStatePID}),
            ThisNodeKey = common_misc:get_agent_server_key(),
            RegisterMsg={agent_reg,ThisNodeKey,node(),StatePID},
            erlang:send(CenterStatePID,RegisterMsg);
        _ ->
            ?ERROR_MSG("center_node server error :~p", [CenterNodeName]),
            net_kernel:disconnect(CenterNodeName)
    end.

do_recv_center_line_state(_CenterServices,NewAllLineList) ->
    OldLineList = data_manager:get_agent_lines(),
    NewAllLineList2 = lists:foldl(fun(LineInfo = #node_connect_state{node_key = NodeKey},Acc) ->
        case lists:keyfind(NodeKey,#node_connect_state.node_key,OldLineList) of
            #node_connect_state{status = ?NODE_USABLE} -> Acc;
            _ -> [LineInfo|Acc]
        end
    end,[],NewAllLineList),
    connect_node(NewAllLineList2,self()).
%% todo data_manager:set_agent_center_state(CenterServices).

%% @todo 检查节点是不是活着
do_check_center_state(_CenterNodeName) ->
    ok.

connect_node([],_AgentPID) ->
    ok;
connect_node([#node_connect_state{node_key = NodeKey,node = NodeName,cookie = NodeCookie,state_pid = StatePID}|LineList],AgentPID) ->
    erlang:spawn(fun() ->
        true = erlang:set_cookie(NodeName, NodeCookie),
        case net_kernel:connect_node(NodeName) of
            true -> erlang:send(AgentPID,{connect_line_ok, NodeKey, NodeName,NodeCookie,StatePID});
            _ -> ignore
        end
    end),
    connect_node(LineList,AgentPID).

do_connect_line_ok(NodeKey,NodeName,NodeCookie,StatePID) ->
    NewState = #node_connect_state{node_key = NodeKey, node = NodeName,cookie = NodeCookie,status = ?NODE_USABLE,state_pid = StatePID},
    data_manager:add_agent_line(NewState).