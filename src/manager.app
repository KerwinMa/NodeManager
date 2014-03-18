%%%-------------------------------------------------------------------
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
{application, manager, [
    {description, "server top engine start"},
    {id,"manager"},
    {vsn, "0.1"},
    {registered, [manager,manager_sup]},
    {applications, [ kernel,stdlib,sasl]},
    {mod, {manager, []}},
    {env, []}
]}.