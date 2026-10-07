%%%-------------------------------------------------------------------
%%% Provider-neutral roster operations for trusted transport components.
%%%-------------------------------------------------------------------

-module(mod_transport).

-behaviour(gen_mod).

-include("xmpp.hrl").
-include("mod_roster.hrl").
-include("logger.hrl").

-export([
    start/2,
    stop/1,
    reload/3,
    depends/2,
    mod_options/1,
    mod_opt_type/1,
    mod_doc/0
]).
-export([decode_iq_subel/1, process_iq/1]).

-define(NS_TRANSPORT_ROSTER, <<"urn:xabber:transport:roster:1">>).

%%====================================================================
%% gen_mod callbacks
%%====================================================================

start(Host, _Opts) ->
    gen_iq_handler:add_iq_handler(
        ejabberd_local,
        Host,
        ?NS_TRANSPORT_ROSTER,
        ?MODULE,
        process_iq
    ).

stop(Host) ->
    gen_iq_handler:remove_iq_handler(
        ejabberd_local,
        Host,
        ?NS_TRANSPORT_ROSTER
    ).

reload(_Host, _NewOpts, _OldOpts) ->
    ok.

depends(_Host, _Opts) ->
    [{mod_roster, hard}].

mod_options(_Host) ->
    [{allowed_components, []}, {iq_auth_secret, <<>>}].

mod_opt_type(allowed_components) ->
    fun normalize_allowed_components/1;
mod_opt_type(iq_auth_secret) ->
    fun to_binary/1;
mod_opt_type(_) ->
    [allowed_components].

mod_doc() ->
    #{
        desc => <<"Provider-neutral roster helper for XMPP transports">>,
        opts => [
            {allowed_components, #{
                value => <<"component domains allowed to manage their roster contacts">>
            }},
            {iq_auth_secret, #{
                value => <<"shared secret used to authenticate roster IQ requests">>
            }}
        ]
    }.

%% Keep the custom payload as raw XML.  The namespace has no xmpp codec
%% record and is deliberately decoded by this small module.
decode_iq_subel(#xmlel{} = El) ->
    El.

%%====================================================================
%% IQ API
%%====================================================================

process_iq(#iq{type = set, lang = Lang} = IQ) ->
    case authorize_iq(IQ) of
        ok ->
            case authenticate_iq(IQ) of
                ok ->
                    process_authorized_iq(IQ);
                {error, Text} ->
                    xmpp:make_error(IQ, xmpp:err_forbidden(Text, Lang))
            end;
        {error, Text} ->
            xmpp:make_error(IQ, xmpp:err_forbidden(Text, Lang))
    end;
process_iq(#iq{lang = Lang} = IQ) ->
    Text = <<"Only IQ requests of type 'set' are allowed">>,
    xmpp:make_error(IQ, xmpp:err_not_allowed(Text, Lang)).

process_authorized_iq(
    #iq{
        lang = Lang,
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = Attrs,
                children = Children
            }
        ]
    } = IQ
) ->
    case {attr(<<"xmlns">>, Attrs), attr(<<"op">>, Attrs)} of
        {?NS_TRANSPORT_ROSTER, Op} when is_binary(Op), Op =/= <<>> ->
            #jid{lserver = RequestHost} = IQ#iq.to,
            #jid{lserver = RequestComponent} = IQ#iq.from,
            Payload = maps:merge(
                fields_to_payload(Children),
                #{request_host => RequestHost, request_component => RequestComponent}
            ),
            operation_result(IQ, run_operation(Op, Payload));
        _ ->
            Text = <<"Malformed transport roster query">>,
            xmpp:make_error(IQ, xmpp:err_bad_request(Text, Lang))
    end;
process_authorized_iq(#iq{lang = Lang} = IQ) ->
    Text = <<"A single transport roster query is required">>,
    xmpp:make_error(IQ, xmpp:err_bad_request(Text, Lang)).

run_operation(<<"add-roster-contact">>, Payload) ->
    upsert_roster_contact(Payload);
run_operation(<<"rename-roster-contact">>, Payload) ->
    upsert_roster_contact(Payload);
run_operation(<<"remove-roster-contact">>, Payload) ->
    remove_roster_contact(Payload);
run_operation(_Operation, _Payload) ->
    {error, <<"Unsupported transport roster operation">>}.

operation_result(IQ, {ok, Status}) ->
    xmpp:make_iq_result(IQ, result_el(Status));
operation_result(#iq{lang = Lang} = IQ, {error, Text}) ->
    xmpp:make_error(IQ, xmpp:err_bad_request(Text, Lang));
operation_result(#iq{lang = Lang} = IQ, {internal_error, Text}) ->
    xmpp:make_error(IQ, xmpp:err_internal_server_error(Text, Lang)).

result_el(Status) ->
    #xmlel{
        name = <<"query">>,
        attrs = [
            {<<"xmlns">>, ?NS_TRANSPORT_ROSTER},
            {<<"status">>, Status}
        ],
        children = []
    }.

%%====================================================================
%% Authorization and validation
%%====================================================================

authorize_iq(
    #iq{
        from = #jid{
            luser = <<>>,
            lserver = Component,
            lresource = <<>>
        },
        to = #jid{
            luser = <<>>,
            lserver = Host,
            lresource = <<>>
        }
    }
) ->
    %% Only a configured external component may ask for roster writes.  User
    %% clients still see normal roster pushes; they never call this private API.
    Allowed = gen_mod:get_module_opt(
        Host,
        ?MODULE,
        allowed_components,
        []
    ),
    case lists:member(Component, Allowed) of
        true ->
            ok;
        false ->
            {error, <<"Transport component is not allowed">>}
    end;
authorize_iq(_) ->
    {error, <<"Transport roster operations require bare component and server JIDs">>}.

authenticate_iq(
    #iq{
        id = IQId,
        to = #jid{lserver = Host},
        sub_els = [#xmlel{attrs = Attrs}]
    }
) when is_binary(IQId), IQId =/= <<>> ->
    Secret = gen_mod:get_module_opt(Host, ?MODULE, iq_auth_secret, <<>>),
    Signature = attr(<<"auth-signature">>, Attrs),
    case {byte_size(Secret) >= 32, decode_hex(Signature)} of
        {true, {ok, Received}} ->
            Expected = crypto:mac(hmac, sha256, Secret, IQId),
            case constant_time_equal(Expected, Received) of
                true -> ok;
                false -> {error, <<"Invalid roster IQ authentication signature">>}
            end;
        {false, _} ->
            {error, <<"Roster IQ authentication secret is not configured">>};
        {_, _} ->
            {error, <<"Invalid roster IQ authentication signature">>}
    end;
authenticate_iq(_) ->
    {error, <<"Roster IQ id and authentication signature are required">>}.

decode_hex(Value) when is_binary(Value), byte_size(Value) =:= 64 ->
    try binary:decode_hex(Value) of
        Decoded -> {ok, Decoded}
    catch
        error:badarg -> error
    end;
decode_hex(_) ->
    error.

constant_time_equal(Left, Right) when byte_size(Left) =:= byte_size(Right) ->
    0 =:= lists:foldl(
        fun({A, B}, Difference) -> Difference bor (A bxor B) end,
        0,
        lists:zip(binary_to_list(Left), binary_to_list(Right))
    );
constant_time_equal(_, _) ->
    false.

validate_owner_and_contact(Payload) ->
    case {
        required_field(owner_jid, Payload),
        required_field(contact_jid, Payload)
    } of
        {{ok, OwnerValue}, {ok, ContactValue}} ->
            validate_owner_and_contact(
                OwnerValue,
                ContactValue,
                maps:get(request_host, Payload, undefined),
                maps:get(request_component, Payload, undefined)
            );
        {{error, Text}, _} ->
            {error, Text};
        {_, {error, Text}} ->
            {error, Text}
    end.

validate_owner_and_contact(
    OwnerValue,
    ContactValue,
    RequestHost,
    RequestComponent
) ->
    case {
        parse_bare_user_jid(OwnerValue),
        parse_bare_user_jid(ContactValue)
    } of
        {{ok, Owner}, {ok, Contact}} ->
            validate_contact_scope(
                RequestHost,
                RequestComponent,
                Owner,
                Contact
            );
        {{error, _}, _} ->
            {error, <<"Invalid owner_jid">>};
        {_, {error, _}} ->
            {error, <<"Invalid contact_jid">>}
    end.

validate_contact_scope(
    RequestHost,
    RequestComponent,
    #jid{lserver = Host} = Owner,
    #jid{lserver = ContactHost} = Contact
) ->
    case Host =:= RequestHost of
        false ->
            {error, <<"owner_jid must belong to the destination server">>};
        true ->
            case ContactHost =:= RequestComponent of
                true ->
                    {ok, Owner, Contact};
                false ->
                    {error, <<"contact_jid must belong to the requesting transport component">>}
            end
    end.

parse_bare_user_jid(Value) ->
    try jid:from_string(Value) of
        #jid{luser = LUser, lserver = LServer, lresource = <<>>} = JID
            when LUser =/= <<>>, LServer =/= <<>> ->
            {ok, jid:remove_resource(JID)};
        _ ->
            {error, invalid}
    catch
        _:_ ->
            {error, invalid}
    end.

required_field(Name, Payload) ->
    case maps:get(Name, Payload, undefined) of
        Value when is_binary(Value), Value =/= <<>> ->
            {ok, Value};
        _ ->
            {error, <<"Missing required field: ", (field_binary(Name))/binary>>}
    end.

field_binary(owner_jid) -> <<"owner_jid">>;
field_binary(contact_jid) -> <<"contact_jid">>;
field_binary(name) -> <<"name">>.

%%====================================================================
%% Roster operations
%%====================================================================

upsert_roster_contact(Payload) ->
    case {
        validate_owner_and_contact(Payload),
        required_field(name, Payload)
    } of
        {{ok, Owner, Contact}, {ok, Name}} ->
            Groups = normalize_groups(maps:get(groups, Payload, [])),
            upsert_roster_contact(Owner, Contact, Name, Groups);
        {{error, Text}, _} ->
            {error, Text};
        {_, {error, Text}} ->
            {error, Text}
    end.

upsert_roster_contact(Owner, Contact, Name, Groups) ->
    OldItem = find_roster_item(Owner, Contact),
    NewItem = roster_item(Owner, Contact, Name, Groups),
    case roster_item_changed(OldItem, NewItem) of
        false ->
            {ok, <<"unchanged">>};
        true ->
            %% mod_roster owns persistence and fan-out semantics.  This module
            %% only builds the roster item after validating transport scope.
            case normalize_transaction_result(mod_roster:set_roster(NewItem)) of
                ok ->
                    push_roster_item(Owner, OldItem, NewItem),
                    {ok, <<"updated">>};
                Error ->
                    ?ERROR_MSG(
                        "mod_transport failed to update roster owner=~s contact=~s error=~p~n",
                        [jid:to_string(Owner), jid:to_string(Contact), Error]
                    ),
                    {internal_error, <<"Roster update failed">>}
            end
    end.

remove_roster_contact(Payload) ->
    case validate_owner_and_contact(Payload) of
        {ok, Owner, Contact} ->
            remove_roster_contact(Owner, Contact);
        {error, Text} ->
            {error, Text}
    end.

remove_roster_contact(Owner, Contact) ->
    case find_roster_item(Owner, Contact) of
        none ->
            {ok, <<"unchanged">>};
        OldItem ->
            LUser = Owner#jid.luser,
            LServer = Owner#jid.lserver,
            LJID = jid:tolower(Contact),
            case normalize_transaction_result(
                mod_roster:del_roster(LUser, LServer, LJID)
            ) of
                ok ->
                    Removed = OldItem#roster{
                        name = <<>>,
                        subscription = remove,
                        ask = none,
                        groups = []
                    },
                    mod_roster:push_item(Owner, OldItem, Removed),
                    {ok, <<"removed">>};
                Error ->
                    ?ERROR_MSG(
                        "mod_transport failed to remove roster owner=~s contact=~s error=~p~n",
                        [jid:to_string(Owner), jid:to_string(Contact), Error]
                    ),
                    {internal_error, <<"Roster removal failed">>}
            end
    end.

roster_item(Owner, Contact, Name, Groups) ->
    LUser = Owner#jid.luser,
    LServer = Owner#jid.lserver,
    LJID = jid:tolower(Contact),
    #roster{
        usj = {LUser, LServer, LJID},
        us = {LUser, LServer},
        jid = LJID,
        name = Name,
        subscription = both,
        ask = none,
        groups = Groups
    }.

find_roster_item(Owner, Contact) ->
    LUser = Owner#jid.luser,
    LServer = Owner#jid.lserver,
    LJID = jid:tolower(Contact),
    case [
        Item
     || #roster{jid = ItemJID} = Item <- mod_roster:get_roster(LUser, LServer),
        ItemJID =:= LJID
    ] of
        [Item | _] ->
            Item;
        [] ->
            none
    end.

roster_item_changed(none, _NewItem) ->
    true;
roster_item_changed(
    #roster{
        name = Name,
        subscription = both,
        ask = none,
        groups = Groups
    },
    #roster{name = Name, groups = Groups}
) ->
    false;
roster_item_changed(#roster{}, #roster{}) ->
    true.

push_roster_item(Owner, none, NewItem) ->
    EmptyItem = NewItem#roster{
        name = <<>>,
        subscription = none,
        ask = none,
        groups = []
    },
    mod_roster:push_item(Owner, EmptyItem, NewItem);
push_roster_item(Owner, OldItem, NewItem) ->
    mod_roster:push_item(Owner, OldItem, NewItem).

normalize_transaction_result(ok) ->
    ok;
normalize_transaction_result({atomic, _Result}) ->
    ok;
normalize_transaction_result(Result) ->
    Result.

%%====================================================================
%% XML and option helpers
%%====================================================================

fields_to_payload(Children) ->
    lists:foldl(fun field_to_payload/2, #{}, Children).

field_to_payload(
    #xmlel{
        name = <<"field">>,
        attrs = Attrs,
        children = Children
    },
    Payload
) ->
    case field_name(attr(<<"name">>, Attrs)) of
        undefined ->
            Payload;
        Name ->
            maps:put(Name, cdata(Children), Payload)
    end;
field_to_payload(
    #xmlel{name = <<"group">>, children = Children},
    Payload
) ->
    Groups = maps:get(groups, Payload, []),
    maps:put(groups, Groups ++ [cdata(Children)], Payload);
field_to_payload(_Element, Payload) ->
    Payload.

field_name(<<"owner_jid">>) -> owner_jid;
field_name(<<"contact_jid">>) -> contact_jid;
field_name(<<"name">>) -> name;
field_name(_) -> undefined.

attr(Name, Attrs) ->
    proplists:get_value(Name, Attrs).

cdata(Children) ->
    iolist_to_binary([
        Data
     || {xmlcdata, Data} <- Children
    ]).

normalize_groups(Groups) when is_list(Groups) ->
    lists:usort([
        Group
     || Group <- Groups,
        is_binary(Group),
        Group =/= <<>>
    ]);
normalize_groups(_) ->
    [].

normalize_allowed_components(Components) when is_list(Components) ->
    [
        jid:nameprep(to_binary(Component))
     || Component <- Components,
        to_binary(Component) =/= <<>>
    ];
normalize_allowed_components(Component) ->
    normalize_allowed_components([Component]).

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value).
