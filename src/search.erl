-module(search).
-compile(export_all).

-import(board, []).

-define(WAIT, 150).
-define(WALL,   1).

%%%%%%%%%%%%%%%%%%%%%
%% HELPERS
%%%%%%%%%%%%%%%%%%%%%

%% Wait function
wait(Mill) ->
    receive
    after Mill -> ok
    end.

%% Index of the minimum
minimum([]) -> error;
minimum([Min]) -> {Min, 1};
minimum([Head|Tail]) -> minimum(Head, Tail, 1, 2).
minimum(Min, [Head|Tail], Index, CIndex) ->
    if
        Head < Min ->
            minimum(Head, Tail, CIndex, CIndex + 1);
        true ->
            minimum(Min, Tail, Index, CIndex + 1)
    end;
minimum(Min, [], Index, _) -> {Min, Index}.

%% Index of a element in a list
index_of(Item, List) -> index_of(Item, List, 1).
index_of(_, [], _) -> not_found;
index_of(Item, [Item|_], Index) -> Index;
index_of(Item, [_|Tail], Index) -> index_of(Item, Tail, Index + 1).

%% Remove the Nth element in a list
delete_nth(_,[]) -> not_found;
delete_nth(Pos,[H|T]) ->
    if
        Pos == 1 -> T;
        true -> lists:append([H], delete_nth(Pos - 1, T))
    end.

%% Euclidean heuristics
euclidean(Dx, Dy) ->
    math:sqrt((Dx * Dx) + (Dy * Dy)).


%%%%%%%%%%%%%%%%%%%%%
%% GREEDY
%%%%%%%%%%%%%%%%%%%%%

%% Greedy process
greedy_proc({Fi, Fj}, {FringeCell, FringeHeu}) ->

    %% Do wait
    wait(?WAIT),

    %% Check if found
    board ! {get_pos, self()},
    receive
        {I, J} when (I == Fi) and (J == Fj) ->
            found;
        {_, _} ->
            %% Jump
            board ! {get_neighbors, self()},
            receive
                {[], _} ->
                    if FringeCell == [] ->
                        io:format("Unable to find the path.~n"),
                        fail;
                    true ->
                        io:format("Problems, got stuck.~n"),
                        %% Move
                        {Val, Min} = minimum(FringeHeu),
                        Next = lists:nth(Min, FringeCell),
                        io:format("Will try to backtrack to ~w.~n", [Next]),
                        board ! {move, Next},
                        %% Remove new search point from Fringe
                        greedy_proc({Fi, Fj},
                                    {lists:delete(Next, FringeCell),
                                     lists:delete(Val, FringeHeu)})
                    end;
                {Cells, Heuristics} ->
                    %% Move
                    {Val, Min} = minimum(Heuristics),
                    Next = lists:nth(Min, Cells),
                    board ! {move, Next},
                    %% Add to Fringe
                    greedy_proc({Fi, Fj},
                                {lists:append(FringeCell,
                                                lists:delete(Next, Cells)),
                                 lists:append(FringeHeu,
                                                lists:delete(Val, Heuristics))})
            end
    end.

%% Spawn greedy
greedy() ->
    board ! {get_finish, self()},
    receive
        {Fi, Fj} ->
            spawn(search, greedy_proc, [{Fi, Fj}, {[], []}])
    end.


%%%%%%%%%%%%%%%%%%%%%
%% A*
%%%%%%%%%%%%%%%%%%%%%

%% A* process
a_star_proc({Si, Sj}, {Fi, Fj}, {FringeCell, FringeHeu}) ->

    %% Do wait
    wait(?WAIT),

    %% Check if found
    board ! {get_pos, self()},
    receive
        {I, J} when (I == Fi) and (J == Fj) ->
            found;
        {_, _} ->
            %% Jump
            board ! {get_neighbors, self()},
            receive
                {[], _} ->
                    if FringeCell == [] ->
                        io:format("Unable to find the path.~n"),
                        fail;
                    true ->
                        io:format("Problems, got stuck.~n"),
                        %% Move
                        {Val, Min} = minimum(FringeHeu),
                        Next = lists:nth(Min, FringeCell),
                        io:format("Will try to backtrack to ~w.~n", [Next]),
                        board ! {move, Next},
                        %% Remove new search point from Fringe
                        a_star_proc({Si, Sj},
                                    {Fi, Fj},
                                    {lists:delete(Next, FringeCell),
                                     lists:delete(Val, FringeHeu)})
                    end;
                {Cells, Heuristics} ->
                    AStarHeuristics = a_star_logic(Heuristics, Cells, {Si, Sj}),
                    %% Add to Fringe
                    NewFringeCell = lists:append(FringeCell, Cells),
                    NewFringeHeu =  lists:append(FringeHeu, AStarHeuristics),
                    %% Move
                    {Val, Min} = minimum(NewFringeHeu),
                    Next = lists:nth(Min, NewFringeCell),
                    board ! {move, Next},
                    a_star_proc({Si, Sj},
                                {Fi, Fj},
                                {lists:delete(Next, NewFringeCell),
                                 lists:delete(Val, NewFringeHeu)})
            end
    end.

%% A* calc for distance traveled plus heuristics.
a_star_logic([F|R], [{Pi, Pj}|RC], {Si, Sj}) ->
    [
        (F + math:sqrt((Pi - Si) * (Pi - Si) + (Pj - Sj) * (Pj - Sj))) |
        a_star_logic(R, RC, {Si, Sj})
    ];
a_star_logic([], _, _) -> [].

%% Spawn A*
a_star() ->
    board ! {get_finish, self()},
    receive
        {Fi, Fj} ->
        board ! {get_pos, self()},
        receive
            {Si, Sj} ->
                spawn(search, a_star_proc, [{Si, Sj}, {Fi, Fj}, {[], []}])
        end
    end.


%%%%%%%%%%%%%%%%%%%%%
%% Jump points
%%%%%%%%%%%%%%%%%%%%%

%% Check if a give coordinate is walkable
is_walkable(Board, X, Y) ->
    Pos = board:calcPos(X, Y),
    if
    Pos == invalid -> false;
    true ->
        case element(Pos, Board) of
        ?WALL ->
            false;
        _ ->
            true
        end
    end.

%% Spawn Jump Points
jump_points() ->
    board ! {get_finish, self()},
    receive
        {Ex, Ey} ->
        board ! {get_pos, self()},
        receive
            {Sx, Sy} ->
            board ! {get_board, self()},
            receive
                Board ->
                spawn(search, jump_points_proc, [
                        [{Sx, Sy}], [none], [0], [0], [{Sx, Sy}], [],
                         {Ex, Ey}, Board
                    ])
            end
        end
    end.

%% Jump Points process
jump_points_proc([], _, _, _, _, _, _, _) ->
    io:format("Unable to find a path.~n"),
    fail;
jump_points_proc(OpenList, Parents, Gs, Fs, Opened, Closed, End = {Ex, Ey}, Board) ->

    {_, Min} = minimum(Gs),

    {Nx, Ny} = lists:nth(Min, OpenList),
    NodeG    = lists:nth(Min, Gs),
    Parent   = lists:nth(Min, Parents),

    NewCl    = lists:append(Closed, [{Nx, Ny}]),
    NewPs    = delete_nth(Min, Parents),
    NewOL    = delete_nth(Min, OpenList),
    NewGs    = delete_nth(Min, Gs),
    NewFs    = delete_nth(Min, Fs),

    if
    ((Nx == Ex) and (Ny == Ey)) ->
        io:format("Destination found.~n"),
        board ! {jump, {Ex, Ey}},
        found;
    true ->
        {ModOL, ModPs, ModGs, ModFs, ModOp, _} = identify_successors(
                                {Nx, Ny}, NodeG, Parent,
                                {NewOL, NewPs, NewGs, NewFs, Opened, NewCl},
                                {Board, {Ex, Ey}}),
        jump_points_proc(
            ModOL, ModPs, ModGs, ModFs, ModOp, NewCl,
            End, Board)
    end.

%% Identify successors for the given node. Runs a jump point search in the
%% direction of each available neighbor, adding any points found to the open
%% list.
%% @return {NewOL, NewPs, NewGs, NewFs} The context of the search.
identify_successors(Node, NodeG, Parent, Context, Payload = {Board, _}) ->
    Neighbors = find_neighbors(Node, Parent, Board),
    NewContext = identify_successors_aux(Node, NodeG, Parent, Neighbors,
                                         Context, Payload,
                                         1, length(Neighbors) + 1),
    NewContext.

identify_successors_aux(_, _, _, _, Context, _, Current, Stop)
        when Current == Stop ->
    Context;
identify_successors_aux(Node = {X, Y}, NodeG, Parent, Neighbors,
                        Context = {OpenList, Parents, Gs, Fs, Opened, Closed},
                        Payload = {_, {Ex, Ey}},
                        Current, Stop) ->
    Next = Current + 1,
    {Nx, Ny} = lists:nth(Current, Neighbors),
    JumpPoint = jump({Nx, Ny, X, Y}, Payload),

    io:format("Considering neighbor ~p.~n", [{Nx, Ny}]),
    wait(?WAIT),

    if
    JumpPoint /= {} ->
        {Jx, Jy} = JumpPoint,
        board ! {jump, {Jx, Jy}},
        JumpPointClosed = lists:member({Jx, Jy}, Closed),
        if
        JumpPointClosed ->
            %% If closed, continue
            identify_successors_aux(Node, NodeG, Parent, Neighbors,
                                    Context, Payload,
                                    Next, Stop);
        true ->
            Dist = euclidean(abs(Jx - X), abs(Jy - Y)),
            Newg = NodeG + Dist,
            JumpPointOpened = lists:member({Jx, Jy}, Opened),
            if
            %% Already opened, requires updates
            JumpPointOpened ->
                IndexJP = index_of({Jx, Jy}, OpenList),
                JPg = lists:nth(IndexJP, Gs),
                if
                Newg < JPg ->
                    Newf  = Newg + euclidean(abs(Jx - Ex), abs(Jy - Ey)),
                    NewOL = lists:append(delete_nth(IndexJP, OpenList), [{Jx, Jy}]),
                    NewPs = lists:append(delete_nth(IndexJP, Parents), [{X, Y}]),
                    NewGs = lists:append(delete_nth(IndexJP, Gs), [Newg]),
                    NewFs = lists:append(delete_nth(IndexJP, Fs), [Newf]),
                    identify_successors_aux(Node, NodeG, Parent, Neighbors,
                                            {NewOL, NewPs, NewGs, NewFs, Opened, Closed},
                                            Payload, Next, Stop);
                %% Opened, but don't requires updates, continue
                true ->
                    identify_successors_aux(Node, NodeG, Parent, Neighbors,
                                            Context, Payload,
                                            Next, Stop)
                end;
            %% Not opened, adding it to the opened list
            true ->
                Newf = Newg + math:sqrt((Nx - Ex) * (Nx - Ex) + (Ny - Ey) * (Ny - Ey)),
                NewOL = lists:append(OpenList,[{Jx,Jy}]),
                NewPs = lists:append(Parents,[{X,Y}]),
                NewGs = lists:append(Gs,[Newg]),
                NewFs = lists:append(Fs,[Newf]),
                NewOpened = lists:append(Opened,[{Jx,Jy}]),
                identify_successors_aux(Node, NodeG, Parent, Neighbors,
                        {NewOL, NewPs, NewGs, NewFs, NewOpened, Closed},
                        Payload, Next, Stop)
            end
        end;

    true ->
        identify_successors_aux(Node, NodeG, Parent, Neighbors,
                                Context, Payload,
                                Next, Stop)
    end.

%% Find the neighbors for the given node. If the node has a parent,
%% prune the neighbors based on the jump point search algorithm, otherwise
%% return all available neighbors.
%% @return [{X1, Y1}, ..., {Xn, Yn}] The neighbors found.
find_neighbors(Pos, none, Board) ->
    %% No parent, return all neighbors
    board:neighbors(Board, Pos);

find_neighbors({X, Y}, {Px, Py}, Board) ->
    %% Get the normalized direction of travel
    Dx = trunc((X - Px) / max(abs(X - Px), 1)),
    Dy = trunc((Y - Py) / max(abs(Y - Py), 1)),
    find_neighbors_aux({X, Y, Dx, Dy}, Board).

%% Search diagonally
find_neighbors_aux({X, Y, Dx, Dy}, Board) when
        ((Dx /= 0) and (Dy /= 0)) ->

    W1 = is_walkable(Board, X, Y + Dy),
    W2 = is_walkable(Board, X + Dx, Y),
    W3 = is_walkable(Board, X, Y + Dy) or is_walkable(Board, X + Dx, Y),
    W4 = not is_walkable(Board, X - Dx, Y) and is_walkable(Board, X, Y + Dy),
    W5 = not is_walkable(Board, X, Y - Dy) and is_walkable(Board, X + Dx, Y),

    L1 = if W1 -> [{X, Y + Dy}]; true -> [] end,
    L2 = if W2 -> lists:append(L1, [{X + Dx, Y}]); true -> L1 end,
    L3 = if W3 -> lists:append(L2, [{X + Dx, Y + Dy}]); true -> L2 end,
    L4 = if W4 -> lists:append(L3, [{X - Dx, Y + Dy}]); true -> L3 end,
    L5 = if W5 -> lists:append(L4, [{X + Dx, Y - Dy}]); true -> L4 end,
    L5;

%% Search horizontally
find_neighbors_aux({X, Y, Dx, Dy}, Board) when Dx == 0 ->
    W1 = is_walkable(Board, X, Y + Dy),
    W2 = W1 and not is_walkable(Board, X + 1, Y),
    W3 = W1 and not is_walkable(Board, X - 1, Y),
    if
    W1 ->
        L1 = [{X, Y + Dy}],
        L2 = if W2 -> lists:append(L1, [{X + 1, Y + Dy}]); true -> L1 end,
        L3 = if W3 -> lists:append(L2, [{X - 1, Y + Dy}]); true -> L2 end,
        L3;
    true ->
        []
    end;

%% Search vertically
find_neighbors_aux({X, Y, Dx, _}, Board) ->
    W1 = is_walkable(Board, X + Dx, Y),
    W2 = W1 and not is_walkable(Board, X, Y + 1),
    W3 = W1 and not is_walkable(Board, X, Y - 1),
    if
    W1 ->
        L1 = [{X + Dx, Y}],
        L2 = if W2 -> lists:append(L1, [{X + Dx, Y + 1}]); true -> L1 end,
        L3 = if W3 -> lists:append(L2, [{X + Dx, Y - 1}]); true -> L2 end,
        L3;
    true ->
        []
    end.


%% Search recursively in the direction (parent -> child), stopping only when a
%% jump point is found.
%% @return {number, number} The x, y coordinate of the jump point found, or
%% empty tuple {} if not found.
jump({X, Y, Px, Py}, Payload = {Board, {Ex, Ey}}) ->

    Dx = X - Px,
    Dy = Y - Py,

    %% Simple cases
    Wall = not is_walkable(Board, X, Y),
    if
    Wall -> {};
    ((X == Ex) and (Y == Ey)) -> {X, Y};

    %% Check for forced neighbors
    true ->
        %% Moving along the diagonal
        Diagonal = ((Dx /= 0) and (Dy /= 0)) and ((
                        is_walkable(Board, X - Dx, Y + Dy) and not
                        is_walkable(Board, X - Dx, Y)
                    ) or (
                        is_walkable(Board, X + Dx, Y - Dy) and not
                        is_walkable(Board, X, Y - Dy)
                    )),
        %% Moving horizontally / vertically
        %%  Moving along X axis
        AlongX = Diagonal or ((Dx /= 0) and ((
                        is_walkable(Board, X + Dx, Y + 1) and not
                        is_walkable(Board, X, Y + 1)
                    ) or (
                        is_walkable(Board, X + Dx, Y - 1) and not
                        is_walkable(Board, X, Y - 1)
                    ))),
        %%  Moving along Y axis
        AlongY = AlongX or ((
                        is_walkable(Board, X + 1, Y + Dy) and not
                        is_walkable(Board, X + 1, Y)
                    ) or (
                        is_walkable(Board, X - 1, Y + Dy) and not
                        is_walkable(Board, X - 1, Y)
                    )),
        if
        Diagonal; AlongX; AlongY -> {X, Y};
        true ->
            %% Special cases with recursive jumps
            %%  When moving diagonally, must check for vertical / horizontal
            %%  jump points
            if
            ((Dx /= 0) and (Dy /= 0)) ->
                Jx = jump({X + Dx, Y, X, Y}, Payload),
                Jy = jump({X, Y + Dy, X, Y}, Payload),
                if
                (Jx /= {}); (Jy /= {}) -> {X, Y};
                true ->
            %%  Moving diagonally, must make sure one of the vertical/horizontal
            %%  neighbors is open to allow the path
                    AllowPath = is_walkable(Board, X + Dx, Y) or
                                is_walkable(Board, X, Y + Dy),
                    if
                    AllowPath -> jump({X + Dx, Y + Dy, X, Y}, Payload);
                    true -> {}
                    end
                end;
            true ->
                AllowPath = is_walkable(Board, X + Dx, Y) or
                            is_walkable(Board, X, Y + Dy),
                if
                AllowPath -> jump({X + Dx, Y + Dy, X, Y}, Payload);
                true -> {}
                end
            end
        end
    end.
