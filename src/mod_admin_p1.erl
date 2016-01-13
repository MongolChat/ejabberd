%%%-------------------------------------------------------------------
%%% File    : mod_admin_p1.erl
%%% Author  : Badlop / Mickael Remond / Christophe Romain
%%% Purpose : Administrative functions and commands for ProcessOne customers
%%% Created : 21 May 2008 by Badlop <badlop@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2016   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%-------------------------------------------------------------------

%%% @doc Administrative functions and commands for ProcessOne customers
%%%
%%% This ejabberd module defines and registers many ejabberd commands
%%% that can be used for performing administrative tasks in ejabberd.
%%%
%%% The documentation of all those commands can be read using ejabberdctl
%%% in the shell.
%%%
%%% The commands can be executed using any frontend to ejabberd commands.
%%% Currently ejabberd_xmlrpc and ejabberdctl. Using ejabberd_xmlrpc it is possible
%%% to call any ejabberd command. However using ejabberdctl not all commands
%%% can be called.

-module(mod_admin_p1).

-author('ProcessOne').

-export([start/2, stop/1,
	% module
	 module_options/1,
	% users
	 create_account/3, delete_account/2,
	% sessions
	 get_resources/2, user_info/2,
	% roster
	 add_rosteritem_groups/5, del_rosteritem_groups/5, modify_rosteritem_groups/6,
	 get_roster/2, get_roster_with_presence/2,
	 set_rosternick/3,
	 transport_register/5,
	% router
	 send_chat/3, send_message/4, send_stanza/3,
	% stats
	 local_sessions_number/0, local_muc_rooms_number/0,
	 p1db_records_number/0, iq_handlers_number/0,
	 server_info/0, server_version/0, server_health/0,
	% mass notification
	 start_mass_message/3, stop_mass_message/1, mass_message/5,
	% mam
	 purge_mam/2]).

-include("ejabberd.hrl").
-include("logger.hrl").
-include("ejabberd_commands.hrl").
-include("mod_roster.hrl").
-include("jlib.hrl").

-define(MASSLOOP, massloop).

-record(session, {usr, us, sid, priority, info}).  % keep in sync with ejabberd_sm.erl

-record(muc_online_room,
	{name_host = {<<"">>, <<"">>} :: {binary(), binary()} | {'_', '$1'} | '$1' | '_',
	 timestamp = p1_time_compat:timestamp() :: erlang:timestamp() | '_',
	 pid = self() :: pid() | '$1' | '$2' | '_'}).


start(_Host, _Opts) ->
    ejabberd_commands:register_commands(commands()).

stop(_Host) ->
    ejabberd_commands:unregister_commands(commands()).

%%%
%%% Register commands
%%%

commands() ->
    [#ejabberd_commands{name = create_account,
			tags = [accounts],
			desc = "Create an ejabberd user account",
			longdesc = "This command is similar to 'register'.",
			module = ?MODULE, function = create_account,
			args =
			    [{user, binary}, {server, binary},
			     {password, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = delete_account,
			tags = [accounts],
			desc = "Remove an account from the server",
			longdesc = "This command is similar to 'unregister'.",
			module = ?MODULE, function = delete_account,
			args = [{user, binary}, {server, binary}],
			result = {res, integer}},
     % XXX Works only for mnesia & odbc, TODO: move to mod_roster
     #ejabberd_commands{name = add_rosteritem_groups,
			tags = [roster],
			desc = "Add new groups in an existing roster item",
			longdesc =
			    "The argument Groups must be a string "
			    "with group names separated by the character ;",
			module = ?MODULE, function = add_rosteritem_groups,
			args =
			    [{user, binary}, {server, binary}, {jid, binary},
			     {groups, binary}, {push, binary}],
			result = {res, integer}},
     % XXX Works only for mnesia & odbc, TODO: move to mod_roster
     #ejabberd_commands{name = del_rosteritem_groups,
			tags = [roster],
			desc = "Delete groups in an existing roster item",
			longdesc =
			    "The argument Groups must be a string "
			    "with group names separated by the character ;",
			module = ?MODULE, function = del_rosteritem_groups,
			args =
			    [{user, binary}, {server, binary}, {jid, binary},
			     {groups, binary}, {push, binary}],
			result = {res, integer}},
     % XXX Works only for mnesia & odbc, TODO: move to mod_roster
     #ejabberd_commands{name = modify_rosteritem_groups,
			tags = [roster],
			desc = "Modify the groups of an existing roster item",
			longdesc =
			    "The argument Groups must be a string "
			    "with group names separated by the character ;",
			module = ?MODULE, function = modify_rosteritem_groups,
			args =
			    [{user, binary}, {server, binary}, {jid, binary},
			     {groups, binary}, {subs, binary}, {push, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = get_roster,
			tags = [roster],
			desc = "Retrieve the roster for a given user",
			longdesc =
			    "Returns a list of the contacts in a "
			    "user roster.\n\nAlso returns the state "
			    "of the contact subscription. Subscription "
			    "can be either  \"none\", \"from\", \"to\", "
			    "\"both\". Pending can be \"in\", \"out\" "
			    "or \"none\".",
                        policy = user,
			module = ?MODULE, function = get_roster,
			args = [],
			result =
			    {contacts,
			     {list,
			      {contact,
			       {tuple,
				[{jid, string},
				 {groups, {list, {group, string}}},
				 {nick, string}, {subscription, string},
				 {pending, string}]}}}}},
     #ejabberd_commands{name = get_roster_with_presence,
			tags = [roster],
			desc =
			    "Retrieve the roster for a given user "
			    "including presence information",
			longdesc =
			    "The 'show' value contains the user presence. "
			    "It can take limited values:\n - available\n "
			    "- chat (Free for chat)\n - away\n - "
			    "dnd (Do not disturb)\n - xa (Not available, "
			    "extended away)\n - unavailable (Not "
			    "connected)\n\n'status' is a free text "
			    "defined by the user client.\n\nAlso "
			    "returns the state of the contact subscription"
			    ". Subscription can be either \"none\", "
			    "\"from\", \"to\", \"both\". Pending "
			    "can be \"in\", \"out\" or \"none\".\n\nNote: "
			    "If user is connected several times, "
			    "only keep the resource with the highest "
			    "non-negative priority.",
			module = ?MODULE, function = get_roster_with_presence,
			args = [{user, binary}, {server, binary}],
			result =
			    {contacts,
			     {list,
			      {contact,
			       {tuple,
				[{jid, string}, {resource, string},
				 {group, string}, {nick, string},
				 {subscription, string}, {pending, string},
				 {show, string}, {status, string}]}}}}},
     % XXX Works only with mnesia or odbc. Doesn't work with
     % s2s. Doesn't work with virtual hosts.
     #ejabberd_commands{name = set_rosternick,
			tags = [roster],
			desc = "Set the nick of an roster item",
			module = ?MODULE, function = set_rosternick,
			args =
			    [{user, binary}, {server, binary},
			     {nick, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = get_resources,
			tags = [session],
			desc = "Get all available resources for a given user",
			module = ?MODULE, function = get_resources,
			args = [{user, binary}, {server, binary}],
			result = {resources, {list, {resource, string}}}},
     #ejabberd_commands{name = transport_register,
			tags = [transports],
			desc = "Register a user in a transport",
			module = ?MODULE, function = transport_register,
			args =
			    [{host, binary}, {transport, binary},
			     {jidstring, binary}, {username, binary},
			     {password, binary}],
			result = {res, string}},
     #ejabberd_commands{name = send_chat,
			tags = [stanza],
			desc = "Send chat message to a given user",
			module = ?MODULE, function = send_chat,
			args = [{from, binary}, {to, binary}, {body, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = send_message,
			tags = [stanza],
			desc = "Send normal message to a given user",
			module = ?MODULE, function = send_message,
			args =
			    [{from, binary}, {to, binary}, {subject, binary},
			     {body, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = send_stanza,
			tags = [stanza],
			desc = "Send stanza to a given user",
			longdesc =
			    "If Stanza contains a \"from\" field, "
			    "then it overrides the passed from argument.If "
			    "Stanza contains a \"to\" field, then "
			    "it overrides the passed to argument.",
			module = ?MODULE, function = send_stanza,
			args =
			    [{user, binary}, {server, binary},
			     {stanza, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = local_sessions_number,
			tags = [stats],
			desc = "Number of sessions in local node",
			module = ?MODULE, function = local_sessions_number,
			args = [],
			result = {res, integer}},
     #ejabberd_commands{name = local_muc_rooms_number,
			tags = [stats],
			desc = "Number of MUC rooms in local node",
			module = ?MODULE, function = local_muc_rooms_number,
			args = [],
			result = {res, integer}},
     #ejabberd_commands{name = p1db_records_number,
			tags = [stats],
			desc = "Number of records in p1db tables",
			module = ?MODULE, function = p1db_records_number,
			args = [],
			result = {modules, {list, {module, {tuple, [{name, string}, {size, integer}]}}}}
		       },
     #ejabberd_commands{name = start_mass_message,
			tags = [stanza],
			desc = "Send chat message or stanza to a mass of users",
			module = ?MODULE, function = start_mass_message,
			args = [{server, binary}, {file, binary}, {rate, integer}],
			result = {res, integer}},
     #ejabberd_commands{name = stop_mass_message,
			tags = [stanza],
			desc = "Force stop of current mass message job",
			module = ?MODULE, function = stop_mass_message,
			args = [{server, binary}],
			result = {res, integer}},
     #ejabberd_commands{name = iq_handlers_number,
			tags = [internal],
			desc = "Number of IQ handlers in the node",
			module = ?MODULE, function = iq_handlers_number,
			args = [],
			result = {res, integer}},
     #ejabberd_commands{name = server_info,
			tags = [stats],
			desc = "Big picture of server use and status",
			module = ?MODULE, function = server_info,
			args = [],
			result = {res, {list,
			    {probe, {tuple, [{name, atom}, {value, integer}]}}}}},
     #ejabberd_commands{name = server_version,
			tags = [],
			desc = "Build version of running server",
			module = ?MODULE, function = server_version,
			args = [],
			result = {res, {list,
			    {probe, {tuple, [{name, atom}, {value, string}]}}}}},
     #ejabberd_commands{name = server_health,
			tags = [stats],
			desc = "Server health, returns warnings or alerts",
			module = ?MODULE, function = server_health,
			args = [],
			result = {res, {list,
			    {probe, {tuple, [{level, atom}, {message, string}]}}}}},
     #ejabberd_commands{name = user_info,
			tags = [session],
			desc = "Information about a user's online sessions",
			module = ?MODULE, function = user_info,
			args = [{user, binary}, {server, binary}],
			result = {res, {tuple, [
				    {status, string},
				    {sessions, {list,
					{session, {list,
					    {info, {tuple, [{name, atom}, {value, string}]}}}}}}]}}},
	  #ejabberd_commands{name = purge_mam,
			     tags = [mam],
			     desc = "Purge MAM archive for old messages",
			     longdesc = "First parameter is virtual host "
			     "name.\n"
			     "Second parameter is the age of messages "
			     "to delete, in days.\n"
			     "It returns the number of deleted messages, "
			     "or a negative error code.",
			     module = ?MODULE, function = purge_mam,
			     args = [{server, binary}, {days, integer}],
			     result = {res, integer}}
    ].


%%%
%%% Erlang
%%%

module_options(Module) ->
    [{Host, proplists:get_value(Module, gen_mod:loaded_modules_with_opts(Host))}
     || Host <- ejabberd_config:get_myhosts()].


%%%
%%% Accounts
%%%

create_account(U, S, P) ->
    case ejabberd_auth:try_register(U, S, P) of
      {atomic, ok} -> 0;
      {atomic, exists} -> 409;
      _ -> 1
    end.

delete_account(U, S) ->
    Fun = fun () -> ejabberd_auth:remove_user(U, S) end,
    user_action(U, S, Fun, ok).


%%%
%%% Sessions
%%%


get_resources(U, S) ->
    case ejabberd_auth:is_user_exists(U, S) of
      true -> get_resources2(U, S);
      false -> 404
    end.

user_info(U, S) ->
    case ejabberd_auth:is_user_exists(U, S) of
	true ->
	    case get_sessions(U, S) of
		[] -> {<<"offline">>, [last_info(U, S)]};
		Ss -> {<<"online">>, [session_info(Session) || Session <- Ss]}
	    end;
	false ->
	    {<<"unregistered">>, [[]]}
    end.

%%%
%%% Vcard
%%%


%%%
%%% Roster
%%%





unlink_contacts(JID1, JID2) ->
    unlink_contacts(JID1, JID2, true).

unlink_contacts(JID1, JID2, Push) ->
    {U1, S1, _} =
	jid:tolower(jid:from_string(JID1)),
    {U2, S2, _} =
	jid:tolower(jid:from_string(JID2)),
    case {ejabberd_auth:is_user_exists(U1, S1),
	  ejabberd_auth:is_user_exists(U2, S2)}
	of
      {true, true} ->
	  case unlink_contacts2(JID1, JID2, Push) of
	    {atomic, ok} -> 0;
	    _ -> 1
	  end;
      _ -> 404
    end.

get_roster(U, S) ->
    case ejabberd_auth:is_user_exists(U, S) of
      true -> format_roster(get_roster2(U, S));
      false -> 404
    end.

get_roster_with_presence(U, S) ->
    case ejabberd_auth:is_user_exists(U, S) of
      true -> format_roster_with_presence(get_roster2(U, S));
      false -> 404
    end.

set_rosternick(U, S, N) ->
    Fun = fun() -> change_rosternick(U, S, N) end,
    user_action(U, S, Fun, ok).

change_rosternick(User, Server, Nick) ->
    LUser = jid:nodeprep(User),
    LServer = jid:nameprep(Server),
    LJID = {LUser, LServer, <<"">>},
    JID = jid:to_string(LJID),
    Push = fun(Subscription) ->
	jlib:iq_to_xml(#iq{type = set, xmlns = ?NS_ROSTER, id = <<"push">>,
			   sub_el = [#xmlel{name = <<"query">>, attrs = [{<<"xmlns">>, ?NS_ROSTER}],
				     children = [#xmlel{name = <<"item">>, attrs = [{<<"jid">>, JID}, {<<"name">>, Nick}, {<<"subscription">>, atom_to_binary(Subscription, utf8)}]}]}]})
	end,
    Result = case roster_backend(Server) of
	mnesia ->
	    %% XXX This way of doing can not work with s2s
	    mnesia:transaction(
		fun() ->
		    lists:foreach(fun(Roster) ->
			{U, S} = Roster#roster.us,
			mnesia:write(Roster#roster{name = Nick}),
			lists:foreach(fun(R) ->
			    UJID = jid:make(U, S, R),
			    ejabberd_router:route(UJID, UJID, Push(Roster#roster.subscription))
			end, get_resources(U, S))
		    end, mnesia:match_object(#roster{jid = LJID, _ = '_'}))
		end);
	odbc ->
	    %%% XXX This way of doing does not work with several domains
	    ejabberd_odbc:sql_transaction(Server,
		fun() ->
		    SNick = ejabberd_odbc:escape(Nick),
		    SJID = ejabberd_odbc:escape(JID),
		    ejabberd_odbc:sql_query_t(
				["update rosterusers"
				 " set nick='", SNick, "'"
				 " where jid='", SJID, "';"]),
		    case ejabberd_odbc:sql_query_t(
			["select username from rosterusers"
			 " where jid='", SJID, "'"
			 " and subscription = 'B';"]) of
			{selected, [<<"username">>], Users} ->
			    lists:foreach(fun({RU}) ->
				lists:foreach(fun(R) ->
				    UJID = jid:make(RU, Server, R),
				    ejabberd_router:route(UJID, UJID, Push(both))
				end, get_resources(RU, Server))
			    end, Users);
			_ ->
			    ok
		    end
		end);
	none ->
	    {error, no_roster}
    end,
    case Result of
	{atomic, ok} -> ok;
	_ -> error
    end.


%%%
%%% Groups of Roster Item
%%%

add_rosteritem_groups(User, Server, JID,
		      NewGroupsString, PushString) ->
    {U1, S1, _} = jid:tolower(jid:from_string(JID)),
    NewGroups = str:tokens(NewGroupsString, <<";">>),
    Push = jlib:binary_to_atom(PushString),
    case {ejabberd_auth:is_user_exists(U1, S1),
	  ejabberd_auth:is_user_exists(User, Server)}
	of
      {true, true} ->
	  case add_rosteritem_groups2(User, Server, JID,
				      NewGroups, Push)
	      of
	    ok -> 0;
	    Error -> ?INFO_MSG("Error found: ~n~p", [Error]), 1
	  end;
      _ -> 404
    end.

del_rosteritem_groups(User, Server, JID,
		      NewGroupsString, PushString) ->
    {U1, S1, _} = jid:tolower(jid:from_string(JID)),
    NewGroups = str:tokens(NewGroupsString, <<";">>),
    Push = jlib:binary_to_atom(PushString),
    case {ejabberd_auth:is_user_exists(U1, S1),
	  ejabberd_auth:is_user_exists(User, Server)}
	of
      {true, true} ->
	  case del_rosteritem_groups2(User, Server, JID,
				      NewGroups, Push)
	      of
	    ok -> 0;
	    Error -> ?INFO_MSG("Error found: ~n~p", [Error]), 1
	  end;
      _ -> 404
    end.

modify_rosteritem_groups(User, Server, JID,
			 NewGroupsString, SubsString, PushString) ->
    Nick = <<"">>,
    Subs = jlib:binary_to_atom(SubsString),
    {_, _, _} = jid:tolower(jid:from_string(JID)),
    NewGroups = str:tokens(NewGroupsString, <<";">>),
    Push = jlib:binary_to_atom(PushString),
    case ejabberd_auth:is_user_exists(User, Server) of
      true ->
	  case modify_rosteritem_groups2(User, Server, JID,
					 NewGroups, Push, Nick, Subs)
	      of
	    ok -> 0;
	    Error -> ?INFO_MSG("Error found: ~n~p", [Error]), 1
	  end;
      _ -> 404
    end.

add_rosteritem_groups2(User, Server, JID, NewGroups,
		       Push) ->
    GroupsFun = fun (Groups) ->
			lists:usort(NewGroups ++ Groups)
		end,
    change_rosteritem_group(User, Server, JID, GroupsFun,
			    Push).

del_rosteritem_groups2(User, Server, JID, NewGroups,
		       Push) ->
    GroupsFun = fun (Groups) -> Groups -- NewGroups end,
    change_rosteritem_group(User, Server, JID, GroupsFun,
			    Push).

modify_rosteritem_groups2(User, Server, JID2, NewGroups,
			  _Push, _Nick, _Subs)
    when NewGroups == [] ->
    JID1 = jid:to_string(jid:make(User, Server,
					    <<"">>)),
    case unlink_contacts(JID1, JID2) of
      0 -> ok;
      Error -> Error
    end;
modify_rosteritem_groups2(User, Server, JID, NewGroups,
			  Push, Nick, Subs) ->
    GroupsFun = fun (_Groups) -> NewGroups end,
    change_rosteritem_group(User, Server, JID, GroupsFun,
			    Push, NewGroups, Nick, Subs).

change_rosteritem_group(User, Server, JID, GroupsFun,
			Push) ->
    change_rosteritem_group(User, Server, JID, GroupsFun,
			    Push, [], <<"">>, <<"both">>).

change_rosteritem_group(User, Server, JID, GroupsFun,
			Push, NewGroups, Nick, Subs) ->
    {RU, RS, _} = jid:tolower(jid:from_string(JID)),
    LJID = {RU, RS, <<>>},
    LUser = jid:nodeprep(User),
    LServer = jid:nameprep(Server),
    Result = case roster_backend(LServer) of
	       mnesia ->
		   mnesia:transaction(fun () ->
					      case mnesia:read({roster,
								{LUser, LServer,
								 LJID}})
						  of
						[#roster{} = Roster] ->
						    NewGroups2 =
							GroupsFun(Roster#roster.groups),
						    NewRoster =
							Roster#roster{groups =
									  NewGroups2},
						    mnesia:write(NewRoster),
						    {ok, NewRoster#roster.name,
						     NewRoster#roster.subscription,
						     NewGroups2};
						_ -> not_in_roster
					      end
				      end);
	       odbc ->
		   ejabberd_odbc:sql_transaction(LServer,
						 fun () ->
							 Username =
							     ejabberd_odbc:escape(User),
							 SJID =
							     ejabberd_odbc:escape(jid:to_string(LJID)),
							 case
							   ejabberd_odbc:sql_query_t([<<"select nick, subscription from rosterusers "
											"      where username='">>,
										      Username,
										      <<"'         and jid='">>,
										      SJID,
										      <<"';">>])
							     of
							   {selected,
							    [<<"nick">>,
							     <<"subscription">>],
							    [[Name,
							      SSubscription]]} ->
							       Subscription =
								   case
								     SSubscription
								       of
								     <<"B">> ->
									 both;
								     <<"T">> ->
									 to;
								     <<"F">> ->
									 from;
								     _ -> none
								   end,
							       Groups = case
									  odbc_queries:get_roster_groups(LServer,
													 Username,
													 SJID)
									    of
									  {selected,
									   [<<"grp">>],
									   JGrps}
									      when
										is_list(JGrps) ->
									      [JGrp
									       || [JGrp]
										      <- JGrps];
									  _ ->
									      []
									end,
							       NewGroups2 =
								   GroupsFun(Groups),
							       ejabberd_odbc:sql_query_t([<<"delete from rostergroups       where "
											    "username='">>,
											  Username,
											  <<"'         and jid='">>,
											  SJID,
											  <<"';">>]),
							       lists:foreach(fun
									       (Group) ->
										   ejabberd_odbc:sql_query_t([<<"insert into rostergroups(           "
														"   username, jid, grp)  values ('">>,
													      Username,
													      <<"','">>,
													      SJID,
													      <<"','">>,
													      ejabberd_odbc:escape(Group),
													      <<"');">>])
									     end,
									     NewGroups2),
							       {ok, Name,
								Subscription,
								NewGroups2};
							   _ -> not_in_roster
							 end
						 end);
	       none -> {atomic, {ok, Nick, Subs, NewGroups}}
	     end,
    case {Result, Push} of
      {{atomic, {ok, Name, Subscription, NewGroups3}},
       true} ->
	  roster_push(User, Server, JID, Name,
		      iolist_to_binary(atom_to_list(Subscription)),
		      NewGroups3),
	  ok;
      {{atomic, {ok, _Name, _Subscription, _NewGroups3}},
       false} ->
	  ok;
      {{atomic, not_in_roster}, _} -> not_in_roster;
      Error -> {error, Error}
    end.

transport_register(Host, TransportString, JIDString,
		   Username, Password) ->
    TransportAtom = jlib:binary_to_atom(TransportString),
    case {lists:member(Host, ?MYHOSTS),
	  jid:from_string(JIDString)}
	of
      {true, JID} when is_record(JID, jid) ->
	  case catch apply(gen_transport, register, [Host, TransportAtom,
					    JIDString, Username, Password])
	      of
	    ok -> <<"OK">>;
	    {error, Reason} ->
		<<"ERROR: ",
		  (iolist_to_binary(atom_to_list(Reason)))/binary>>;
	    {'EXIT', {timeout, _}} -> <<"ERROR: timed_out">>;
	    {'EXIT', _} -> <<"ERROR: unexpected_error">>
	  end;
      {false, _} -> <<"ERROR: unknown_host">>;
      _ -> <<"ERROR: bad_jid">>
    end.

%%%
%%% Stanza
%%%

send_chat(FromJID, ToJID, Msg) ->
    From = jid:from_string(FromJID),
    To = jid:from_string(ToJID),
    Stanza = #xmlel{name = <<"message">>,
		    attrs = [{<<"type">>, <<"chat">>}],
		    children =
			[#xmlel{name = <<"body">>, attrs = [],
				children = [{xmlcdata, Msg}]}]},
    ejabberd_router:route(From, To, Stanza),
    0.

send_message(FromJID, ToJID, Sub, Msg) ->
    From = jid:from_string(FromJID),
    To = jid:from_string(ToJID),
    Stanza = #xmlel{name = <<"message">>,
		    attrs = [{<<"type">>, <<"normal">>}],
		    children =
			[#xmlel{name = <<"subject">>, attrs = [],
				children = [{xmlcdata, Sub}]},
			 #xmlel{name = <<"body">>, attrs = [],
				children = [{xmlcdata, Msg}]}]},
    ejabberd_router:route(From, To, Stanza),
    0.

send_stanza(FromJID, ToJID, StanzaStr) ->
    case xml_stream:parse_element(StanzaStr) of
      {error, _} -> 1;
      Stanza ->
	  #xmlel{attrs = Attrs} = Stanza,
	  From =
	      jid:from_string(proplists:get_value(<<"from">>,
						     Attrs, FromJID)),
	  To = jid:from_string(proplists:get_value(<<"to">>,
						      Attrs, ToJID)),
	  ejabberd_router:route(From, To, Stanza),
	  0
    end.

start_mass_message(Host, File, Rate)
	when is_binary(Host), is_binary(File), is_integer(Rate) ->
    From = jid:make(<<>>, Host, <<>>),
    Proc = gen_mod:get_module_proc(Host, ?MASSLOOP),
    Delay = 60000 div Rate,
    case global:whereis_name(Proc) of
	undefined ->
	    case mass_message_parse_file(File) of
		{error, _} -> 4;
		{ok, _, []} -> 3;
		{ok, <<>>, _} -> 2;
		{ok, Body, Tos} when is_binary(Body) ->
		    Stanza = #xmlel{name = <<"message">>,
			    attrs = [{<<"type">>, <<"chat">>}],
			    children = [#xmlel{name = <<"body">>, attrs = [],
					    children = [{xmlcdata, Body}]}]},
		    Pid = spawn(?MODULE, mass_message, [Host, Delay, Stanza, From, Tos]),
		    global:register_name(Proc, Pid),
		    0;
		{ok, Stanza, Tos} ->
		    Pid = spawn(?MODULE, mass_message, [Host, Delay, Stanza, From, Tos]),
		    global:register_name(Proc, Pid),
		    0
	    end;
	_ ->
	    % return error if loop already/still running
	    1
    end.

stop_mass_message(Host) ->
    Proc = gen_mod:get_module_proc(Host, ?MASSLOOP),
    case global:whereis_name(Proc) of
	undefined -> 1;
	Pid -> Pid ! stop, 0
    end.

%%%
%%% Stats
%%%

local_sessions_number() ->
    Iterator = fun(#session{sid = {_, Pid}}, Acc)
		  when node(Pid) == node() ->
		       Acc+1;
		  (_Session, Acc) ->
		       Acc
	       end,
    F = fun() -> mnesia:foldl(Iterator, 0, session) end,
    mnesia:ets(F).

local_muc_rooms_number() ->
    Iterator = fun(#muc_online_room{pid = Pid}, Acc)
		  when node(Pid) == node() ->
		       Acc+1;
		  (_Room, Acc) ->
		       Acc
	       end,
    F = fun() -> mnesia:foldl(Iterator, 0, muc_online_room) end,
    mnesia:ets(F).

p1db_records_number() ->
    [{atom_to_list(Table), Count} || Table <- p1db:opened_tables(),
		       {ok, Count} <- [p1db:count(Table)]].

%%%
%%% Misc
%%%

iq_handlers_number() ->
    ets:info(sm_iqtable, size).

server_info() ->
    Hosts = ejabberd_config:get_myhosts(),
    Memory = erlang:memory(total),
    Processes = erlang:system_info(process_count),
    IqHandlers = iq_handlers_number(),
    Nodes = ejabberd_cluster:get_nodes(),
    {LocalSessions, LocalFailed} = ejabberd_cluster:multicall(Nodes, ?MODULE, local_sessions_number, []),
    Sessions = ets:info(session, size),
    OdbcPoolSize = lists:sum(
	    [workers_number(gen_mod:get_module_proc(Host, ejabberd_odbc_sup))
		|| Host <- Hosts]),
    HttpPoolSize = case catch http_p1:get_pool_size() of
	{'EXIT', _} -> 0;
	Size -> Size
    end,
    {Jabs, {MegaSecs,Secs,_}} = lists:foldr(fun(Host, {J,S}) ->
		    case catch mod_jabs:value(Host) of
			{'EXIT', _} -> {J,S};
			{Int, Now} -> {J+Int, Now};
			_ -> {J,S}
		    end
	    end, {0, os:timestamp()}, Hosts),
    JabsSince = MegaSecs*1000000+Secs,
    DefaultActive = [{<<"daily_active_users">>, 0},
		     {<<"weekly_active_users">>, 0},
		     {<<"monthly_active_users">>, 0}],
    [FirstActive | OtherActive] =
	[lists:sort(ejabberd_command(active_counters, [Host], DefaultActive))
		|| Host <- Hosts],
    ActiveAll = lists:foldl(
	fun(Counters, Acc) ->
	    lists:zipwith(
		fun({Key, A}, {Key, B}) -> {Key, A+B} end,
		Acc, lists:sort(Counters))
	end, FirstActive, OtherActive),
    lists:flatten([
	[{online, Sessions} | lists:zip(Nodes--LocalFailed, LocalSessions)],
	[{jlib:binary_to_atom(Key), Val} || {Key, Val} <- ActiveAll],
	{jabs, Jabs},
	{jabs_since, JabsSince},
	{memory, Memory},
	{processes, Processes},
	{iq_handlers, IqHandlers},
	{odbc_pool_size, OdbcPoolSize},
	{http_pool_size, HttpPoolSize}
	]).

server_version() ->
    {ok, Version} = application:get_key(ejabberd, vsn),
    {ok, Modules} = application:get_key(ejabberd, modules),
    [{Build,Secs}|Stamps] = lists:usort([build_stamp(M) || M<-Modules]),
    [{Patch, Last}|_] = lists:reverse(Stamps),
    [{version, list_to_binary(Version)}, {build, Build} | [{patch, Patch} || Last-Secs > 120]].

server_health() ->
    Hosts = ejabberd_config:get_myhosts(),
    Health = lists:usort(lists:foldl(
		fun(Host, Acc) ->
			case catch mod_mon:value(Host, health) of
			    H when is_list(H) -> H++Acc;
			    _ -> Acc
			end
		end, [], Hosts)),
    [{Level, <<Componant/binary, ": ", Message/binary>>}
     || {Level, Componant, Message} <- Health].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Internal functions

%% -----------------------------
%% Internal roster handling
%% -----------------------------

get_roster2(User, Server) ->
    LUser = jid:nodeprep(User),
    LServer = jid:nameprep(Server),
    ejabberd_hooks:run_fold(roster_get, LServer, [], [{LUser, LServer}]).



del_rosteritem(User, Server, JID, Push) ->
    {RU, RS, _} = jid:tolower(jid:from_string(JID)),
    LJID = {RU, RS, <<>>},
    Result = case roster_backend(Server) of
	       mnesia ->
		   mnesia:transaction(fun () ->
					      mnesia:delete({roster,
							     {User, Server,
							      LJID}})
				      end);
	       odbc ->
		   case ejabberd_odbc:sql_transaction(Server,
						      fun () ->
							      Username =
								  ejabberd_odbc:escape(User),
							      SJID =
								  ejabberd_odbc:escape(jid:to_string(LJID)),
							      odbc_queries:del_roster(Server,
										      Username,
										      SJID)
						      end)
		       of
		     {atomic, _} -> {atomic, ok};
		     Error -> Error
		   end;
	       none -> {atomic, ok}
	     end,
    case {Result, Push} of
      {{atomic, ok}, true} ->
	  roster_push(User, Server, JID, <<"">>, <<"remove">>,
		      []);
      {{atomic, ok}, false} -> ok;
      _ -> error
    end,
    Result.

unlink_contacts2(JID1, JID2, Push) ->
    {U1, S1, _} =
	jid:tolower(jid:from_string(JID1)),
    {U2, S2, _} =
	jid:tolower(jid:from_string(JID2)),
    case del_rosteritem(U1, S1, JID2, Push) of
      {atomic, ok} -> del_rosteritem(U2, S2, JID1, Push);
      Error -> Error
    end.

roster_push(User, Server, JID, Nick, Subscription,
	    Groups) ->
    TJID = jid:from_string(JID),
    {TU, TS, _} = jid:tolower(TJID),

    mod_roster:invalidate_roster_cache(jid:nodeprep(User), jid:nameprep(Server)),

    Presence = #xmlel{name = <<"presence">>,
		      attrs =
			  [{<<"type">>,
			    case Subscription of
			      <<"remove">> -> <<"unsubscribed">>;
			      <<"none">> -> <<"unsubscribe">>;
			      <<"both">> -> <<"subscribed">>;
			      _ -> <<"subscribe">>
			    end}],
		      children = []},
    ItemAttrs = case Nick of
		  <<"">> ->
		      [{<<"jid">>, JID}, {<<"subscription">>, Subscription}];
		  _ ->
		      [{<<"jid">>, JID}, {<<"name">>, Nick},
		       {<<"subscription">>, Subscription}]
		end,
    ItemGroups = lists:map(fun (G) ->
				   #xmlel{name = <<"group">>, attrs = [],
					  children = [{xmlcdata, G}]}
			   end,
			   Groups),
    Result = jlib:iq_to_xml(#iq{type = set,
				xmlns = ?NS_ROSTER, id = <<"push">>,
				lang = <<"langxmlrpc-en">>,
				sub_el =
				    [#xmlel{name = <<"query">>,
					    attrs = [{<<"xmlns">>, ?NS_ROSTER}],
					    children =
						[#xmlel{name = <<"item">>,
							attrs = ItemAttrs,
							children =
							    ItemGroups}]}]}),
    lists:foreach(fun (Resource) ->
			  UJID = jid:make(User, Server, Resource),
			  ejabberd_router:route(TJID, UJID, Presence),
			  ejabberd_router:route(UJID, UJID, Result),
			  case Subscription of
			    <<"remove">> -> none;
			    _ ->
				lists:foreach(fun (TR) ->
						      ejabberd_router:route(jid:make(TU,
											  TS,
											  TR),
									    UJID,
									    #xmlel{name
										       =
										       <<"presence">>,
										   attrs
										       =
										       [],
										   children
										       =
										       []})
					      end,
					      get_resources(TU, TS))
			  end
		  end,
		  [R || R <- get_resources(User, Server)]).

roster_backend(Server) ->
    Modules = gen_mod:loaded_modules(Server),
    Mnesia = lists:member(mod_roster, Modules),
    Odbc = lists:member(mod_roster_odbc, Modules),
    if Mnesia -> mnesia;
       true ->
	   if Odbc -> odbc;
	      true -> none
	   end
    end.

format_roster([]) -> [];
format_roster(Items) -> format_roster(Items, []).

format_roster([], Structs) -> Structs;
format_roster([#roster{jid = JID, name = Nick,
		       groups = Group, subscription = Subs, ask = Ask}
	       | Items],
	      Structs) ->
    JidBinary = jid:to_string(jid:make(JID)),
    Struct = {JidBinary, Group,
	      Nick, iolist_to_binary(atom_to_list(Subs)),
	      iolist_to_binary(atom_to_list(Ask))},
    format_roster(Items, [Struct | Structs]).

format_roster_with_presence([]) -> [];
format_roster_with_presence(Items) ->
    format_roster_with_presence(Items, []).

format_roster_with_presence([], Structs) -> Structs;
format_roster_with_presence([#roster{jid = JID,
				     name = Nick, groups = Group,
				     subscription = Subs, ask = Ask}
			     | Items],
			    Structs) ->
    {User, Server, _R} = JID,
    Presence = case Subs of
		 both -> get_presence2(User, Server);
		 from -> get_presence2(User, Server);
		 _Other -> {<<"">>, <<"unavailable">>, <<"">>}
	       end,
    {Resource, Show, Status} = Presence,
    Struct = {jid:to_string(jid:make(User, Server, <<>>)),
	      Resource, extract_group(Group), Nick,
	      iolist_to_binary(atom_to_list(Subs)),
	      iolist_to_binary(atom_to_list(Ask)), Show, Status},
    format_roster_with_presence(Items, [Struct | Structs]).

extract_group([]) -> [];
%extract_group([Group|_Groups]) -> Group.
extract_group(Groups) -> str:join(Groups, <<";">>).

%% -----------------------------
%% Internal session handling
%% -----------------------------

get_presence2(User, Server) ->
    case get_sessions(User, Server) of
      [] -> {<<"">>, <<"unavailable">>, <<"">>};
      Ss ->
	  Session = hd(Ss),
	  if Session#session.priority >= 0 ->
		 Pid = element(2, Session#session.sid),
		 {_User, Resource, Show, Status} =
		     ejabberd_c2s:get_presence(Pid),
		 {Resource, Show, Status};
	     true -> {<<"">>, <<"unavailable">>, <<"">>}
	  end
    end.

get_resources2(User, Server) ->
    lists:map(fun (S) -> element(3, S#session.usr) end,
	      get_sessions(User, Server)).

get_sessions(User, Server) ->
    Result = ejabberd_sm:get_user_sessions(User, Server),
    lists:reverse(lists:keysort(#session.priority,
				clean_session_list(Result))).

clean_session_list(Ss) ->
    clean_session_list(lists:keysort(#session.usr, Ss), []).

clean_session_list([], Res) -> Res;
clean_session_list([S], Res) -> [S | Res];
clean_session_list([S1, S2 | Rest], Res) ->
    if S1#session.usr == S2#session.usr ->
	   if S1#session.sid > S2#session.sid ->
		  clean_session_list([S1 | Rest], Res);
	      true -> clean_session_list([S2 | Rest], Res)
	   end;
       true -> clean_session_list([S2 | Rest], [S1 | Res])
    end.

mass_message_parse_file(File) ->
    case file:open(File, [read]) of
	{ok, IoDevice} ->
	    case mass_message_parse_body(IoDevice) of
		{ok, Header} when is_binary(Header) ->
		    Packet = case xml_stream:parse_element(Header) of
			    {error, _} -> Header;  % Header is message Body
			    Stanza -> Stanza       % Header is xmpp stanza
			end,
		    Uids = case mass_message_parse_uids(IoDevice) of
			    {ok, List} when is_list(List) -> List;
			    _ -> []
			end,
		    file:close(IoDevice),
		    {ok, Packet, Uids};
		Error ->
		    file:close(IoDevice),
		    Error
	    end;
	Error ->
	    Error
    end.

mass_message_parse_body(IoDevice) ->
    mass_message_parse_body(IoDevice, file:read_line(IoDevice), <<>>).
mass_message_parse_body(_IoDevice, {ok, "\n"}, Acc) -> {ok, Acc};
mass_message_parse_body(IoDevice, {ok, Data}, Acc) ->
    [Line|_] = binary:split(list_to_binary(Data), <<"\n">>),
    NextLine = file:read_line(IoDevice),
    mass_message_parse_body(IoDevice, NextLine, <<Acc/binary, Line/binary>>);
mass_message_parse_body(_IoDevice, eof, Acc) -> {ok, Acc};
mass_message_parse_body(_IoDevice, Error, _) -> Error.

mass_message_parse_uids(IoDevice) ->
    mass_message_parse_uids(IoDevice, file:read_line(IoDevice), []).
mass_message_parse_uids(IoDevice, {ok, Data}, Acc) ->
    [Uid|_] = binary:split(list_to_binary(Data), <<"\n">>),
    NextLine = file:read_line(IoDevice),
    mass_message_parse_uids(IoDevice, NextLine, [Uid|Acc]);
mass_message_parse_uids(_IoDevice, eof, Acc) -> {ok, lists:reverse(Acc)};
mass_message_parse_uids(_IoDevice, Error, _) -> Error.

mass_message(_Host, _Delay, _Stanza, _From, []) -> done;
mass_message(Host, Delay, Stanza, From, [Uid|Others]) ->
    receive stop ->
	    Proc = gen_mod:get_module_proc(Host, ?MASSLOOP),
	    ?ERROR_MSG("~p mass messaging stopped~n"
		       "Was about to send message to ~s~n"
		       "With ~p remaining recipients",
		    [Proc, Uid, length(Others)]),
	    stopped
    after Delay ->
	    To = case jid:make(Uid, Host, <<>>) of
		error -> jid:from_string(Uid);
		Ret -> Ret
	    end,
	    Attrs = lists:keystore(<<"id">>, 1, Stanza#xmlel.attrs,
			{<<"id">>, <<"job:", (randoms:get_string())/binary>>}),
	    ejabberd_router:route(From, To, Stanza#xmlel{attrs = Attrs}),
	    mass_message(Host, Delay, Stanza, From, Others)
    end.

%% -----------------------------
%% MAM
%% -----------------------------

purge_mam(Host, Days) ->
    case lists:member(Host, ?MYHOSTS) of
	true ->
	    purge_mam(Host, Days, gen_mod:db_type(Host, mod_mam));
	_ ->
	    ?ERROR_MSG("Unknown Host name: ~s", [Host]),
	    -1
    end.

purge_mam(Host, Days, odbc) ->
    Timestamp = p1_time_compat:system_time(micro_seconds) - (3600*24 * Days * 1000000),
    case ejabberd_odbc:sql_query(Host,
				 [<<"DELETE FROM archive "
				   "WHERE timestamp < ">>,
				  integer_to_binary(Timestamp),
				  <<";">>]) of
	{updated, N} ->
	    N;
	_Err ->
	    ?ERROR_MSG("Cannot purge MAM on Host ~s: ~p~n", [Host, _Err]),
	    -1
    end;
purge_mam(_Host, _Days, _Backend) ->
    ?ERROR_MSG("MAM purge not implemented for backend ~p~n",
	       [_Backend]),
    -2.


%% -----------------------------
%% Internal function pattern
%% -----------------------------

user_action(User, Server, Fun, OK) ->
    case ejabberd_auth:is_user_exists(User, Server) of
      true ->
	  case catch Fun() of
	    OK -> 0;
	    _ -> 1
	  end;
      false -> 404
    end.

session_info(#session{info = Info, sid = {Sid, Pid}}) ->
    Node = node(Pid),
    {_User, Resource, Show, _Status} = ejabberd_c2s:get_presence(Pid),
    {IP, Port} = proplists:get_value(ip, Info),
    IpString = jlib:ip_to_list({IP, Port}), %% this just convert IP
    PortString = integer_to_binary(Port),
    ConnMod = proplists:get_value(conn, Info),
    ConnDateTime = calendar:now_to_local_time(Sid),
    [{resource, Resource},
     {presence, Show},
     {since, jlib:timestamp_to_iso(ConnDateTime)},
     {node, jlib:atom_to_binary(Node)},
     {ip, <<IpString/binary, ":", PortString/binary>>},
     {conn, jlib:atom_to_binary(ConnMod)}].

last_info(U, S) ->
    case catch mod_last:get_last_info(U, S) of
	{ok, T1, Reason} ->
	    LastDateTime = calendar:now_to_local_time(seconds_to_now(T1)),
	    %T2 = now_to_seconds(os:timestamp()),
	    %{Days, {H, M, _S}} = calendar:seconds_to_daystime(T2-T1),
	    [{last, jlib:timestamp_to_iso(LastDateTime)},
	     {reason, Reason}];
	_ ->
	    []
    end.

ejabberd_command(Cmd, Args, Default) ->
    case catch ejabberd_commands:execute_command(Cmd, Args) of
	{'EXIT', _} -> Default;
	{error, _} -> Default;
	Result -> Result
    end.

workers_number(Supervisor) ->
    case whereis(Supervisor) of
	undefined -> 0;
	_ -> proplists:get_value(active, supervisor:count_children(Supervisor))
    end.

%now_to_seconds({MegaSecs, Secs, _MicroSecs}) ->
%    MegaSecs * 1000000 + Secs.

seconds_to_now(Secs) ->
    {Secs div 1000000, Secs rem 1000000, 0}.

build_stamp(Module) ->
    {Y,M,D,HH,MM,SS} = proplists:get_value(time, Module:module_info(compile)),
    DateTime = {{Y,M,D},{HH,MM,SS}},
    {jlib:timestamp_to_iso(DateTime), calendar:datetime_to_gregorian_seconds(DateTime)}.
