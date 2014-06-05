-module(bumperl).

-export([main/1]).

-define(OPTSPEC,
        [ {app_file, $a, "app",    string,           ".app or .app.src file"},
          {label,    $l, "label",  atom,             "major | minor | patch"},
          {commit,   $c, "commit", {boolean, false}, "Automatic git commit"},
          {tag,      $t, "tag",    {boolean, false}, "Automatic git tag (implies commit)"} ]
       ).

-record(state, {
          opts      :: proplists:proplist(),
          app_file  :: string(),
          label     :: major | minor | patch,
          app_data  :: any(),
          commit    :: boolean(),
          tag       :: boolean(),

          % opaque :-[
          current   :: semver:version(),
          bumped    :: semver:version()
         }).

main(Args) ->
    init(Args),
    halt(0).

init(Args)
  when is_list(Args) ->
    S1 = #state{},
    Parsed = getopt:parse(?OPTSPEC, Args),
    S2 = init_state(Parsed, S1),
    run(S2).

init_state({error, _Reason}, _) ->
    usage();
init_state({ok, {[], _}}, _) ->
    usage();
init_state({ok, {Opts, _}}, S) ->
    AppFile    = req_arg(app_file, Opts),
    Label      = req_arg(label, Opts),
    AutoTag    = req_arg(tag, Opts),
    AutoCommit = case AutoTag of
                     true ->
                         true;
                     false ->
                         req_arg(commit, Opts)
                 end,
    S#state{
      app_file = AppFile,
      commit   = AutoCommit,
      label    = Label,
      opts     = Opts,
      tag      = AutoTag
      }.

req_arg(K, L) ->
    case lists:keyfind(K, 1, L) of
        {K, V} ->
            V;
        false ->
            io:format(standard_error, "Argument '~p' is required.~n", [K]),
            usage()
    end.

run(S = #state{}) ->
    Steps = [ {read_app_file , fun s_read_app_file/1},
              {parse_version , fun s_parse_version/1},
              {bump_version  , fun s_bump_version/1},
              {save_app_file , fun s_save_app_file/1},
              {maybe_commit  , fun s_maybe_commit/1},
              {maybe_tag     , fun s_maybe_tag/1}
            ],
    lists:foldl(fun({Step, F}, State) ->
                        case F(State) of
                            {ok, NewState = #state{}} ->
                                NewState;
                            {error, Reason} ->
                                io:format(standard_error, "Error during step: "
                                          "~s (~p)~n", [Step, Reason]),
                                halt(1)
                        end
                end, S, Steps).


s_read_app_file(S = #state{app_file=AppFile}) ->
    case file:consult(AppFile) of
        {ok, [{application, _, _}] = D} ->
            {ok, S#state{ app_data = D }};
        {ok, D} ->
            {error, {invalid_app_data, {AppFile, D}}};
        {error, Reason} ->
            {error, {AppFile, Reason}}
    end.

s_parse_version(S = #state{app_data = [{application, _, D}]}) ->
    case lists:keyfind(vsn, 1, D) of
        {vsn, Vsn} ->
            CurrentVsn = mouture:parse(Vsn),
            {ok, S#state{ current = CurrentVsn }};
        false ->
            {error, {no_version_found, D}}
    end.

s_bump_version(S = #state{current = {{Ma,Mi,Pa},Pre,Meta}, label = major}) ->
    {ok, S#state{ bumped = {{Ma+1, Mi, Pa}, Pre, Meta}}};
s_bump_version(S = #state{current = {{Ma,Mi,Pa},Pre,Meta}, label = minor}) ->
    {ok, S#state{ bumped = {{Ma, Mi+1, Pa}, Pre, Meta}}};
s_bump_version(S = #state{current = {{Ma,Mi,Pa},Pre,Meta}, label = patch}) ->
    {ok, S#state{ bumped = {{Ma, Mi, Pa+1}, Pre, Meta}}};
s_bump_version(#state{label = Unknown}) ->
    {error, {invalid_label, Unknown}}.

s_save_app_file(S = #state{ app_file = AppFile, app_data = Data, bumped = Bumped}) ->
    [{application, Name, D}] = Data,
    Vsn = binary_to_list(mouture:unparse(Bumped)),
    NewData = lists:keyreplace(vsn, 1, D, {vsn, Vsn}),
    ok = unconsult(AppFile, [{application, Name, NewData}]),
    io:format("~s~n", [Vsn]),
    {ok, S}.

s_maybe_commit(S = #state{ commit = false }) ->
    {ok, S};
s_maybe_commit(S = #state{ app_file = AppFile, commit = true}) ->
    case run_cmd("git add "++AppFile) of
        {ok, _} ->
            case run_cmd("git commit "++AppFile++" -m 'Bump version'") of
                {ok, _} ->
                    {ok, S};
                {error, Reason} ->
                    {error, {git_commit_failed, Reason}}
            end;
        {error, Reason} ->
            {error, {git_add_failed, Reason}}
    end.

s_maybe_tag(S = #state{ tag = false }) ->
    {ok, S};
s_maybe_tag(S = #state{ tag = true, bumped = Bumped}) ->
    Vsn = binary_to_list(mouture:unparse(Bumped)),
    case run_cmd("git tag "++Vsn) of
        {ok, _} ->
            {ok, S};
        {error, Reason} ->
            {error, {git_tag_failed, Reason}}
    end.

unconsult(F, L) ->
    {ok, S} = file:open(F, write),
    lists:foreach(fun(X) -> io:format(S, "~p.~n", [X]) end, L),
    file:close(S).

usage() ->
    getopt:usage(?OPTSPEC, "bumperl"),
    halt(1).

run_cmd(Cmd) ->
    Port = erlang:open_port({spawn,Cmd}, [exit_status,eof,stderr_to_stdout]),
    run_cmd_loop(Port, [], 2000).

run_cmd_loop(Port, Buffer, Timeout) ->
    receive
        {Port, {data, Data}} ->
            run_cmd_loop(Port, Buffer++Data, Timeout);
        {Port, {exit_status, 0}} ->
            {ok, Buffer};
        {Port, {exit_status, S}} ->
            {error, {exit, S}}
    after Timeout ->
        {error, timeout}
    end.
