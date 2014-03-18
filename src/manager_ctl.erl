%%%-------------------------------------------------------------------
%%% @doc 用于manager_ctl
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(manager_ctl).

-export([start/0,
    init/0,
    process/1,
    func/1,
    func_all/1
]).

-include("common.hrl").


start() ->
    case init:get_plain_arguments() of
        [SNode | Args]->
            SNode1 = case string:tokens(SNode, "@") of
                         [_Node, _Server] -> SNode;
                         _ ->
                             case net_kernel:longnames() of
                                 true ->
                                     SNode ++ "@" ++ inet_db:gethostname() ++ "." ++ inet_db:res_option(domain);
                                 false ->
                                     SNode ++ "@" ++ inet_db:gethostname();
                                 _ ->
                                     SNode
                             end
                     end,
            Node = erlang:list_to_atom(SNode1),
            case erlang:length(Args) > 1 of
                true ->
                    [Command | Args2] = Args,
                    case Command of
                    %% 目前只能支持热更新的单独命令
                        "func" ->
                            Status = case rpc:call(Node, ?MODULE, func, [Args2]) of
                                         {badrpc, Reason} ->
                                             ?PRINT("RPC failed on the node ~w: ~w~n",
                                                 [Node, Reason]),
                                             ?STATUS_BADRPC;
                                         S ->
                                             S
                                     end;
                        "func_all" ->
                            Status = case rpc:call(Node, ?MODULE, func_all, [Args2]) of
                                         {badrpc, Reason} ->
                                             ?PRINT("RPC failed on the node ~w: ~w~n",
                                                 [Node, Reason]),
                                             ?STATUS_BADRPC;
                                         S -> S
                                     end;
                        _ ->
                            ?PRINT("RPC failed on the node ~w: ~s~n",
                                [Node, "not support"]),
                            Status = ?STATUS_BADRPC
                    end;
                false ->
                    Status = case rpc:call(Node, ?MODULE, process, [Args]) of
                                 {badrpc, Reason} ->
                                     ?PRINT("RPC failed on the node ~w: ~w~n",
                                         [Node, Reason]),
                                     ?STATUS_BADRPC;
                                 S -> S
                             end
            end,
            halt(Status);
        _ ->
            print_usage(),
            halt(?STATUS_USAGE)
    end.

init() ->
    ets:new(manager_ctl_cmds, [named_table, set, public]),
    ets:new(manager_ctl_host_cmds, [named_table, set, public]),
    ok.

process(["status"]) ->
    {InternalStatus, ProvidedStatus} = init:get_status(),
    ?PRINT("Node ~w is ~w. Status: ~w~n",
        [node(), InternalStatus, ProvidedStatus]),
    case lists:keysearch(manager, 1, application:which_applications()) of
        false ->
            ?PRINT("node is not running~n", []),
            ?STATUS_ERROR;
        {value,_Version} ->
            ?PRINT("node is running~n", []),
            ?STATUS_SUCCESS
    end;

process(["stop"]) ->
    init:stop(),
    ?STATUS_SUCCESS;

process(["stop_all"]) ->
    init:stop(),
    ?STATUS_SUCCESS;

process(["restart"]) ->
    init:restart(),
    ?STATUS_SUCCESS;

process(_) ->
    print_usage().

func([Module, Method | Args]) ->
    Module2 = common_tool:list_to_atom(Module),
    Method2 = common_tool:list_to_atom(Method),
    ?ERROR_MSG("~ts:~s ~s", ["ready to run func ", Module2, Method2]),
    try
        erlang:apply(Module2, Method2, []),
        ?ERROR_MSG("~ts:~s ~s", ["run func ok", Module2, Method2]),
        ?STATUS_SUCCESS
    catch E:E2 ->
        ?ERROR_MSG("~ts:~w ~w, args:~w", ["run func error", E, E2, Args]),
        ?STATUS_ERROR
    end.

func_all([Module, Method | Args]) ->
    Module2 = common_tool:list_to_atom(Module),
    Method2 = common_tool:list_to_atom(Method),
    ?ERROR_MSG("~ts:~s ~s", ["ready run func all ", Module2, Method2]),
    try
        lists:foreach(
            fun(Node) ->
                rpc:call(Node, Module2, Method2, [])
            end, [node() | nodes()]),
        ?ERROR_MSG("~ts:~s ~s", ["run func all ok", Module2, Method2]),
        ?STATUS_SUCCESS
    catch E:E2 ->
        ?ERROR_MSG("~ts:~w ~w, args:~w", ["run func all error", E, E2, Args]),
        ?STATUS_ERROR
    end.

print_usage() ->
    CmdDescs =
        [{"status", "get node status"},
            {"stop", "stop node"},
            {"restart", "restart node"}
        ] ++
        ets:tab2list(manager_ctl_cmds),
    MaxCmdLen =
        lists:max(lists:map(
            fun({Cmd, _Desc}) ->
                length(Cmd)
            end, CmdDescs)),
    NewLine = io_lib:format("~n", []),
    FmtCmdDescs =
        lists:map(
            fun({Cmd, Desc}) ->
                ["  ", Cmd, string:chars($\s, MaxCmdLen - length(Cmd) + 2),
                    Desc, NewLine]
            end, CmdDescs),
    ?PRINT(
        "Usage: serverctl [--node nodename] command [options]~n"
        "~n"
        "Available commands in this node node:~n"
        ++ FmtCmdDescs ++
            "~n"
            "Examples:~n"
            "  serverctl restart~n"
            "  serverctl --node node@host restart~n"
            "  serverctl vhost www.example.org ...~n",
        []).
