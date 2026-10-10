defmodule ForkmateWeb.GameLive do
  @moduledoc """
  LiveView for playing and exploring a chess game with branching.
  """
  use ForkmateWeb, :live_view

  alias Forkmate.Chess.{Position, Square}
  alias Forkmate.Games
  alias Forkmate.Games.Events.MoveMade
  alias Forkmate.Games.ReadModels.Node
  alias ForkmateWeb.GameComponents

  @impl true
  def mount(%{"id" => game_id} = params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Forkmate.PubSub, "game:" <> game_id)
    end

    case Games.get_game(game_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Game not found.")
         |> push_navigate(to: ~p"/")}

      game ->
        perspective = parse_perspective(params["as"])

        socket =
          socket
          |> assign(
            game_id: game_id,
            perspective: perspective,
            guide: false,
            birdview: false,
            selected_square: nil,
            targets: [],
            promotion_targets: []
          )
          |> load_game_state(game, game.current_node_id)

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"id" => game_id} = params, _uri, socket) do
    perspective = parse_perspective(params["as"])

    case Games.get_game(game_id) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      game ->
        node_id = params["node"] || game.current_node_id

        socket =
          socket
          |> assign(perspective: perspective)
          |> load_game_state(game, node_id)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:game_updated, game_id, event}, socket) do
    if socket.assigns.game_id == game_id do
      game = Games.get_game!(game_id)
      # Follow to the new node if we were on the previous latest node, or on the
      # node the move was just played from (a rewound player branching or continuing).
      view_node_id =
        if socket.assigns.current_node_id == socket.assigns.game.current_node_id or
             played_from?(event, socket.assigns.current_node_id) do
          game.current_node_id
        else
          socket.assigns.current_node_id
        end

      {:noreply, load_game_state(socket, game, view_node_id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_square", %{"square" => square}, socket) do
    case socket.assigns.selected_square do
      nil ->
        select_square_if_piece(socket, square)

      ^square ->
        {:noreply, clear_square_selection(socket)}

      selected ->
        if square in socket.assigns.targets do
          execute_player_move(socket, selected, square)
        else
          select_square_if_piece(socket, square)
        end
    end
  end

  @impl true
  def handle_event("select_node", %{"id" => node_id}, socket) do
    {:noreply,
     socket
     |> load_game_state(socket.assigns.game, node_id)
     |> assign(selected_square: nil, targets: [], promotion_targets: [])}
  end

  @impl true
  def handle_event("toggle_guide", _params, socket) do
    {:noreply, assign(socket, guide: !socket.assigns.guide)}
  end

  @impl true
  def handle_event("toggle_birdview", _params, socket) do
    {:noreply, assign(socket, birdview: !socket.assigns.birdview)}
  end

  @impl true
  def handle_event("switch_perspective", _params, socket) do
    new_perspective = if socket.assigns.perspective == :white, do: :black, else: :white
    {:noreply, assign(socket, perspective: new_perspective)}
  end

  @impl true
  def handle_event("offer_draw", _params, socket) do
    player_id = current_player_id(socket.assigns.game, socket.assigns.perspective)

    case Games.offer_draw(socket.assigns.game_id, player_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Draw offered.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot offer draw: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("accept_draw", _params, socket) do
    player_id = current_player_id(socket.assigns.game, socket.assigns.perspective)

    case Games.accept_draw(socket.assigns.game_id, player_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Draw accepted.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot accept draw: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("decline_draw", _params, socket) do
    player_id = current_player_id(socket.assigns.game, socket.assigns.perspective)

    case Games.decline_draw(socket.assigns.game_id, player_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Draw declined.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot decline draw: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("resign", _params, socket) do
    player_id = current_player_id(socket.assigns.game, socket.assigns.perspective)

    case Games.resign(socket.assigns.game_id, player_id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "You resigned.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot resign: #{inspect(reason)}")}
    end
  end

  # --- Internal Helpers ---

  defp find_node(all_nodes, candidate_ids) do
    Enum.find_value(candidate_ids, fn id -> Enum.find(all_nodes, &(&1.id == id)) end)
  end

  defp played_from?(%MoveMade{parent_node_id: parent_id}, node_id), do: parent_id == node_id
  defp played_from?(_event, _node_id), do: false

  defp select_square_if_piece(socket, square) do
    %{current_node: node, perspective: perspective} = socket.assigns

    if piece_selectable?(node, square, perspective) do
      {:noreply,
       assign(socket,
         selected_square: square,
         targets: Games.legal_targets(node, square),
         promotion_targets: Games.promotion_targets(node, square)
       )}
    else
      {:noreply, clear_square_selection(socket)}
    end
  end

  defp clear_square_selection(socket) do
    assign(socket, selected_square: nil, targets: [], promotion_targets: [])
  end

  defp execute_player_move(socket, selected, square) do
    %{current_node: node, game: game, perspective: perspective} = socket.assigns
    player_id = current_player_id(game, perspective)
    promo_piece = if Games.promotion_move?(node, selected, square), do: :queen, else: nil

    case Games.make_move(%{
           game_id: game.id,
           from_node_id: node.id,
           from: selected,
           to: square,
           promotion: promo_piece,
           player_id: player_id
         }) do
      :ok ->
        {:noreply, clear_square_selection(socket)}

      {:error, reason} ->
        {:noreply,
         socket
         |> clear_square_selection()
         |> put_flash(:error, "Move failed: #{inspect(reason)}")}
    end
  end

  defp load_game_state(socket, game, node_id) do
    all_nodes = Games.list_nodes(game.id)
    graph_nodes = Enum.map(all_nodes, &Node.to_component_map/1)
    fork_ids = Games.find_fork_node_ids(all_nodes)

    current_node = find_node(all_nodes, [node_id, game.current_node_id]) || List.last(all_nodes)

    current_node_id = (current_node && current_node.id) || game.root_node_id
    line_nodes = Games.get_line_nodes(all_nodes, current_node_id)

    line_moves =
      line_nodes
      |> Enum.reject(&(&1.ply == 0))
      |> Enum.map(&%{id: &1.id, ply: &1.ply, san: &1.san})

    active_turn = current_node && Games.turn_color(current_node)

    last_move =
      current_node && current_node.from_square && current_node.to_square &&
        {current_node.from_square, current_node.to_square}

    cursors = %{
      socket.assigns.perspective => current_node_id
    }

    assign(socket,
      game: game,
      all_nodes: all_nodes,
      graph_nodes: graph_nodes,
      fork_ids: fork_ids,
      current_node_id: current_node_id,
      current_node: current_node,
      line_moves: line_moves,
      active_turn: active_turn,
      last_move: last_move,
      check_square: current_node && current_node.check_square,
      cursors: cursors
    )
  end

  defp parse_perspective("black"), do: :black
  defp parse_perspective(_), do: :white

  defp current_player_id(game, :white), do: game.white_player_id
  defp current_player_id(game, :black), do: game.black_player_id

  defp piece_selectable?(%Node{fen: fen}, square, perspective) do
    with {:ok, pos} <- Position.from_fen(fen),
         sq_idx when sq_idx != nil <- Square.from_name(square),
         {piece_color, _} <- Map.get(pos.board, sq_idx) do
      # Friendly piece that matches active turn
      piece_color == pos.active_color and piece_color == perspective
    else
      _ -> false
    end
  end

  defp piece_selectable?(_, _, _), do: false

  # --- Template ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <header class="mb-6 flex flex-wrap items-center justify-between gap-4 border-b border-base-300 pb-4">
          <div class="flex items-center gap-4">
            <h1 class="text-2xl font-bold tracking-tight">Forkmate</h1>
            <span class={[
              "badge",
              if(@game.status == "ended", do: "badge-error", else: "badge-success")
            ]}>
              {@game.status |> String.capitalize()}
            </span>
          </div>

          <div class="flex items-center gap-3">
            <button
              type="button"
              phx-click="switch_perspective"
              class="btn btn-sm btn-outline"
              title="Flip perspective between White and Black"
            >
              Playing as: <strong>{@perspective |> Atom.to_string() |> String.capitalize()}</strong>
              (Flip)
            </button>
            <GameComponents.birdview_toggle on={@birdview} />
          </div>
        </header>

        <%!-- Draw Offer Banner --%>
        <div
          :if={
            @game.draw_offered_by && @game.draw_offered_by != current_player_id(@game, @perspective)
          }
          class="mb-6"
        >
          <GameComponents.draw_offer
            from={
              if @game.draw_offered_by == @game.white_player_id,
                do: @game.white_player_id,
                else: @game.black_player_id
            }
            on_accept="accept_draw"
            on_decline="decline_draw"
          />
        </div>

        <%!-- Game or Branch Result Banner --%>
        <div
          :if={@game.status == "ended" || (@current_node && @current_node.status != "open")}
          class="mb-6"
        >
          <GameComponents.game_result
            reason={result_reason(@game, @current_node)}
            winner={result_winner(@game, @current_node)}
            scope={if @game.status == "ended", do: :game, else: :branch}
          />
        </div>

        <div class="grid grid-cols-1 gap-8 lg:grid-cols-12">
          <%!-- Left Column: Chess Board and Players --%>
          <div class="lg:col-span-7 flex flex-col items-center">
            <% top_player =
              if @perspective == :white, do: @game.black_player_id, else: @game.white_player_id %>
            <% top_color = if @perspective == :white, do: :black, else: :white %>
            <% bottom_player =
              if @perspective == :white, do: @game.white_player_id, else: @game.black_player_id %>
            <% bottom_color = if @perspective == :white, do: :white, else: :black %>

            <div class="w-full max-w-xl flex flex-col gap-3">
              <GameComponents.player_card
                name={top_player}
                color={top_color}
                active={@active_turn == top_color and @game.status != "ended"}
              />

              <div class="relative">
                <GameComponents.board
                  id="main-chess-board"
                  fen={(@current_node && @current_node.fen) || @game.current_fen}
                  orientation={@perspective}
                  last_move={@last_move}
                  selected={@selected_square}
                  targets={@targets}
                  promotion_targets={@promotion_targets}
                  guide={@guide}
                  check={@check_square}
                  on_select="select_square"
                />
              </div>

              <GameComponents.player_card
                name={bottom_player}
                color={bottom_color}
                active={@active_turn == bottom_color and @game.status != "ended"}
              />

              <div class="mt-2 flex items-center justify-between">
                <GameComponents.game_controls
                  guide={@guide}
                  draw_pending={@game.draw_offered_by == current_player_id(@game, @perspective)}
                  disabled={@game.status == "ended"}
                  on_resign="resign"
                  on_offer_draw="offer_draw"
                  on_toggle_guide="toggle_guide"
                />

                <GameComponents.guide_status
                  piece={@selected_square}
                  count={length(@targets)}
                />
              </div>
            </div>
          </div>

          <%!-- Right Column: Move List & Branch Graph --%>
          <div class="lg:col-span-5 flex flex-col gap-6">
            <%!-- Move List for the selected branch --%>
            <div class="rounded-box border border-base-300 bg-base-200/50 p-4">
              <div class="mb-3 flex items-center justify-between border-b border-base-300 pb-2">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/70">
                  Move History
                </h2>
                <span class="text-xs text-base-content/50">
                  Node: <span class="font-mono text-primary">{@current_node_id}</span>
                </span>
              </div>

              <div class="max-h-56 overflow-y-auto pr-1">
                <GameComponents.move_list
                  moves={@line_moves}
                  current={@current_node_id}
                  forks={@fork_ids}
                  on_select="select_node"
                />
              </div>
            </div>

            <%!-- Branch Overview Graph --%>
            <div class="rounded-box border border-base-300 bg-base-200/50 p-4">
              <div class="mb-3 flex items-center justify-between border-b border-base-300 pb-2">
                <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/70">
                  Branch Overview ({length(@graph_nodes)} nodes)
                </h2>
                <span class="text-xs text-base-content/50">Click any node to rewind or branch</span>
              </div>

              <GameComponents.branch_graph
                id="game-branch-graph"
                nodes={@graph_nodes}
                current={@current_node_id}
                cursors={@cursors}
                birdview={@birdview}
                on_select="select_node"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @game_end_reasons %{
    "checkmate" => :checkmate,
    "stalemate" => :stalemate,
    "resignation" => :resignation,
    "agreed_draw" => :agreed_draw,
    "fifty_move" => :fifty_move,
    "repetition" => :repetition,
    "insufficient_material" => :insufficient_material,
    "timeout" => :timeout
  }

  defp result_reason(%{status: "ended", end_reason: reason}, _) when is_binary(reason) do
    Map.get(@game_end_reasons, reason, :agreed_draw)
  end

  defp result_reason(_, %Node{status: "resigned"}), do: :resignation

  defp result_reason(_, %Node{status: status}) when is_binary(status) do
    Map.get(@game_end_reasons, status, :agreed_draw)
  end

  defp result_reason(_, _), do: :checkmate

  defp result_winner(%{status: "ended", winner: winner}, _) when is_binary(winner) do
    case winner do
      "white" -> :white
      "black" -> :black
      _ -> nil
    end
  end

  defp result_winner(_, %Node{status: "checkmate", mover: mover}) when is_binary(mover) do
    # The mover delivered checkmate, so mover won
    case mover do
      "white" -> :white
      "black" -> :black
      _ -> nil
    end
  end

  defp result_winner(_, _), do: nil
end
