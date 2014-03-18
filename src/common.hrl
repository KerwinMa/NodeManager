

-define(CALL_TIMETOUT,5000).
%% 连接成功后多长时间才开启可用模式
-define(CONFIRM_OK_TIMES,3000).
%%5秒循环检查下连接状态
-define(FIVE_LOOP_SECOND,5000).

%% @todo 放入存储介质中
-define(ERROR_MSG(Format,Msg),io:format(Format,Msg)).

%%连接状态
-record(node_connect_state,{node_key, status=0, node, cookie, state_pid, other_infos=[]}).

-define(CENTER_KEYS,9999999).

-define(NODE_DISCONN,0).%%节点未连接
-define(NODE_ESTABLISH,1).%%节点已连接
-define(NODE_USABLE,2).%%节点已链接，可应用


-define(STATUS_SUCCESS, 0).
-define(STATUS_ERROR,   1).
-define(STATUS_USAGE,   2).
-define(STATUS_BADRPC,  3).

-define(TCP_OPTS, [
    binary,
    {packet, 2},
    {reuseaddr, true},
    {nodelay, false},
    {delay_send, true},
    {active, false},
    {exit_on_close, false},
    {send_timeout, 3000}
]).

-define(PRINT(Format, Args),
    io:format(Format, Args)).

-define(_LANG_MANAGER_CTL_DO_OUT_FUNC,"以执行外部方法 ").





