defmodule ForkmateWeb.GameComponents do
  @moduledoc """
  Presentational components for the chess game screen.

  These components only render data handed to them. They never run chess rules:
  legal targets, check squares, SAN and FENs all come from the `Game` aggregate
  and its read models (see `docs/design-brainstorm.md`).
  """
  use Phoenix.Component

  @files ~w(a b c d e f g h)

  @glyphs %{
    "k" => "♚",
    "q" => "♛",
    "r" => "♜",
    "b" => "♝",
    "n" => "♞",
    "p" => "♟"
  }

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  # ---------------------------------------------------------------------------
  # Board
  # ---------------------------------------------------------------------------

  @doc """
  An 8x8 SVG board drawn from the piece-placement field of a FEN string.

  Squares are named in algebraic notation (`"e4"`). Pass `on_select` to make every
  square clickable; the square name is sent as `phx-value-square`.
  """
  attr :id, :string, default: "board"
  attr :fen, :string, default: @start_fen
  attr :orientation, :atom, values: [:white, :black], default: :white
  attr :last_move, :any, default: nil, doc: "`{from, to}` squares of the move that led here"
  attr :selected, :string, default: nil, doc: "square of the piece being moved"
  attr :targets, :list, default: [], doc: "squares the selected piece may move to"

  attr :promotion_targets, :list,
    default: [],
    doc: "subset of `targets` where the move promotes; drawn with a ♛ badge"

  attr :guide, :boolean,
    default: false,
    doc: "guide mode: tint every target square and draw a line along each direction"

  attr :check, :string, default: nil, doc: "square of the king in check"
  attr :on_select, :any, default: nil, doc: "event name or JS command for square clicks"
  attr :class, :any, default: nil

  def board(assigns) do
    pieces = parse_placement(assigns.fen)

    assigns =
      assign(assigns,
        squares: for(rank <- 8..1//-1, file <- 0..7, do: {file, rank}),
        pieces: pieces,
        last_squares: List.wrap(assigns.last_move && Tuple.to_list(assigns.last_move)),
        rays: if(assigns.guide, do: guide_rays(assigns), else: [])
      )

    ~H"""
    <svg
      id={@id}
      viewBox="0 0 8.6 8.6"
      role="img"
      aria-label="Chess board"
      class={["w-full max-w-xl select-none rounded-box shadow-sm", @class]}
    >
      <g transform="translate(0.3 0.15)">
        <g
          :for={{file, rank} <- @squares}
          transform={"translate(#{col(file, @orientation)} #{row(rank, @orientation)})"}
        >
          <% square = square_name(file, rank) %>
          <% piece = @pieces[{file, rank}] %>
          <rect
            width="1"
            height="1"
            fill={if rem(file + rank, 2) == 0, do: "#b58863", else: "#f0d9b5"}
            phx-click={@on_select}
            phx-value-square={square}
            class={@on_select && "cursor-pointer"}
          />
          <rect
            :if={@guide && square in @targets}
            width="1"
            height="1"
            fill={if piece, do: "#f56565", else: "#48bb78"}
            fill-opacity="0.4"
            pointer-events="none"
          />
          <rect
            :if={square in @last_squares}
            width="1"
            height="1"
            fill="#f6e05e"
            fill-opacity="0.55"
            pointer-events="none"
          />
          <rect
            :if={square == @selected}
            width="1"
            height="1"
            fill="#63b3ed"
            fill-opacity="0.6"
            pointer-events="none"
          />
          <rect
            :if={square == @check}
            width="1"
            height="1"
            fill="#e53e3e"
            fill-opacity="0.7"
            pointer-events="none"
          />
          <text
            :if={piece}
            x="0.5"
            y="0.78"
            text-anchor="middle"
            font-size="0.82"
            pointer-events="none"
            fill={if piece_color(piece) == :white, do: "#fffdf5", else: "#1a1a1a"}
            stroke={if piece_color(piece) == :white, do: "#1a1a1a", else: "#fffdf5"}
            stroke-width="0.025"
            paint-order="stroke"
          >
            {glyph(piece)}
          </text>
          <circle
            :if={square in @targets && !piece}
            cx="0.5"
            cy="0.5"
            r="0.16"
            fill="#1a1a1a"
            fill-opacity="0.3"
            pointer-events="none"
          />
          <text
            :if={square in @promotion_targets}
            x="0.86"
            y="0.28"
            text-anchor="middle"
            font-size="0.3"
            pointer-events="none"
            class="fill-base-content"
          >
            {glyph("q")}
          </text>
          <circle
            :if={square in @targets && piece}
            cx="0.5"
            cy="0.5"
            r="0.45"
            fill="none"
            stroke="#1a1a1a"
            stroke-opacity="0.45"
            stroke-width="0.09"
            pointer-events="none"
          />
        </g>
        <line
          :for={{x1, y1, x2, y2} <- @rays}
          x1={x1}
          y1={y1}
          x2={x2}
          y2={y2}
          stroke="#2f855a"
          stroke-opacity="0.55"
          stroke-width="0.1"
          stroke-linecap="round"
          pointer-events="none"
        />
        <text
          :for={i <- 0..7}
          x={i + 0.5}
          y="8.28"
          text-anchor="middle"
          font-size="0.24"
          class="fill-base-content/70"
        >
          {file_label(i, @orientation)}
        </text>
        <text
          :for={i <- 0..7}
          x="-0.16"
          y={i + 0.62}
          text-anchor="middle"
          font-size="0.24"
          class="fill-base-content/70"
        >
          {rank_label(i, @orientation)}
        </text>
      </g>
    </svg>
    """
  end

  defp parse_placement(fen) do
    [placement | _] = String.split(fen, " ")

    placement
    |> String.split("/")
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, i} -> parse_row(row, 8 - i) end)
    |> Map.new()
  end

  defp parse_row(row, rank) do
    {cells, _file} =
      row
      |> String.graphemes()
      |> Enum.reduce({[], 0}, fn char, {cells, file} ->
        case Integer.parse(char) do
          {empty, ""} -> {cells, file + empty}
          _ -> {[{{file, rank}, char} | cells], file + 1}
        end
      end)

    cells
  end

  # One line per straight direction (rank, file or diagonal) from the selected
  # square to the farthest target in that direction. Pure geometry: which
  # squares are targets still comes from the aggregate. Knight jumps are not
  # straight, so they get no line.
  defp guide_rays(%{selected: nil}), do: []

  defp guide_rays(%{selected: selected, targets: targets, orientation: orientation}) do
    {sf, sr} = square_coords(selected)

    targets
    |> Enum.map(&square_coords/1)
    |> Enum.map(fn {f, r} -> {f - sf, r - sr} end)
    |> Enum.filter(fn {df, dr} -> straight?(df, dr) end)
    |> Enum.group_by(fn {df, dr} -> {sign(df), sign(dr)} end)
    |> Enum.map(fn {_dir, offsets} ->
      {df, dr} = Enum.max_by(offsets, fn {df, dr} -> max(abs(df), abs(dr)) end)

      {col(sf, orientation) + 0.5, row(sr, orientation) + 0.5, col(sf + df, orientation) + 0.5,
       row(sr + dr, orientation) + 0.5}
    end)
  end

  defp straight?(df, dr), do: (df == 0 or dr == 0 or abs(df) == abs(dr)) and {df, dr} != {0, 0}
  defp sign(n), do: if(n > 0, do: 1, else: if(n < 0, do: -1, else: 0))

  defp square_coords(<<file, rank>>), do: {file - ?a, rank - ?0}

  defp col(file, :white), do: file
  defp col(file, :black), do: 7 - file
  defp row(rank, :white), do: 8 - rank
  defp row(rank, :black), do: rank - 1

  defp square_name(file, rank), do: Enum.at(@files, file) <> Integer.to_string(rank)
  defp file_label(i, :white), do: Enum.at(@files, i)
  defp file_label(i, :black), do: Enum.at(@files, 7 - i)
  defp rank_label(i, :white), do: 8 - i
  defp rank_label(i, :black), do: i + 1

  defp piece_color(piece), do: if(piece == String.upcase(piece), do: :white, else: :black)
  # U+FE0E forces text presentation so the pawn is not drawn as an emoji.
  defp glyph(piece), do: Map.fetch!(@glyphs, String.downcase(piece)) <> "︎"

  # ---------------------------------------------------------------------------
  # Player card and clock
  # ---------------------------------------------------------------------------

  @doc "A player's name, rating and clock, shown above and below the board."
  attr :name, :string, required: true
  attr :rating, :integer, default: nil
  attr :color, :atom, values: [:white, :black], required: true
  attr :active, :boolean, default: false, doc: "true when it is this player's turn"
  attr :online, :boolean, default: true
  attr :seconds, :integer, default: nil, doc: "remaining time; nil for untimed games"
  attr :class, :any, default: nil

  def player_card(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-between gap-3 rounded-box border px-3 py-2 transition-colors",
      if(@active, do: "border-primary bg-primary/10", else: "border-base-300 bg-base-200"),
      @class
    ]}>
      <div class="flex min-w-0 items-center gap-2">
        <span
          class={[
            "size-4 shrink-0 rounded-full border border-base-content/40",
            if(@color == :white, do: "bg-white", else: "bg-neutral")
          ]}
          title={"Plays #{@color}"}
        />
        <span class="truncate font-semibold">{@name}</span>
        <span :if={@rating} class="text-sm text-base-content/60">({@rating})</span>
        <span
          class={[
            "size-2 shrink-0 rounded-full",
            if(@online, do: "bg-success", else: "bg-base-content/30")
          ]}
          title={if @online, do: "Online", else: "Disconnected"}
        />
      </div>
      <.clock :if={@seconds} seconds={@seconds} running={@active} />
    </div>
    """
  end

  @doc "A game clock in `m:ss` form. Turns red under 20 seconds."
  attr :seconds, :integer, required: true
  attr :running, :boolean, default: false

  def clock(assigns) do
    ~H"""
    <span class={[
      "rounded-field px-2 py-0.5 font-mono text-lg tabular-nums",
      cond do
        @seconds < 20 && @running -> "bg-error text-error-content"
        @running -> "bg-base-content text-base-100"
        true -> "bg-base-300 text-base-content/70"
      end
    ]}>
      {format_clock(@seconds)}
    </span>
    """
  end

  defp format_clock(seconds) do
    minutes = div(seconds, 60)
    secs = seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{minutes}:#{secs}"
  end

  # ---------------------------------------------------------------------------
  # Move list
  # ---------------------------------------------------------------------------

  @doc """
  The moves of the line currently shown, two plies per row.

  `moves` are maps with `:id`, `:ply` and `:san`, ordered by ply. A move whose node has
  siblings gets a fork marker so players can tell there is a branch to visit.
  """
  attr :moves, :list, required: true
  attr :current, :string, default: nil, doc: "id of the node being viewed"
  attr :forks, :list, default: [], doc: "ids of nodes that have more than one child"
  attr :on_select, :any, default: nil, doc: "event name or JS command; sends `phx-value-id`"

  def move_list(assigns) do
    assigns = assign(assigns, :rows, Enum.chunk_every(assigns.moves, 2))

    ~H"""
    <ol class="grid grid-cols-[2.5rem_1fr_1fr] gap-y-0.5 text-sm">
      <li :for={[white | rest] <- @rows} class="col-span-3 grid grid-cols-subgrid items-center">
        <span class="pr-2 text-right text-base-content/50">{div(white.ply + 1, 2)}.</span>
        <.move_cell move={white} current={@current} forks={@forks} on_select={@on_select} />
        <.move_cell
          :if={rest != []}
          move={hd(rest)}
          current={@current}
          forks={@forks}
          on_select={@on_select}
        />
      </li>
    </ol>
    """
  end

  attr :move, :map, required: true
  attr :current, :string, required: true
  attr :forks, :list, required: true
  attr :on_select, :any, required: true

  defp move_cell(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_select}
      phx-value-id={@move.id}
      class={[
        "flex items-center gap-1 rounded-field px-2 py-0.5 text-left font-mono hover:bg-base-300",
        @move.id == @current && "bg-primary text-primary-content hover:bg-primary"
      ]}
    >
      {@move.san}
      <span :if={@move.id in @forks} class="text-xs opacity-70" title="Branch point">⑂</span>
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # Controls, offers and result
  # ---------------------------------------------------------------------------

  @doc "Guide toggle, resign and draw controls under the board."
  attr :guide, :boolean, default: false, doc: "true when guide mode shows legal moves"
  attr :draw_pending, :boolean, default: false, doc: "true after you offered a draw"
  attr :disabled, :boolean, default: false
  attr :on_resign, :any, default: "resign"
  attr :on_offer_draw, :any, default: "offer_draw"
  attr :on_toggle_guide, :any, default: "toggle_guide"

  def game_controls(assigns) do
    ~H"""
    <div class="flex gap-2">
      <button
        type="button"
        class={["btn btn-sm", @guide && "btn-primary"]}
        phx-click={@on_toggle_guide}
        aria-pressed={to_string(@guide)}
      >
        <span aria-hidden="true">{if @guide, do: "💡", else: "○"}</span>
        Guide {if @guide,
          do: "on",
          else: "off"}
      </button>
      <button
        type="button"
        class="btn btn-sm"
        phx-click={@on_offer_draw}
        disabled={@disabled || @draw_pending}
      >
        {if @draw_pending, do: "Draw offered", else: "Offer draw"}
      </button>
      <button
        type="button"
        class="btn btn-sm btn-error btn-outline"
        phx-click={@on_resign}
        disabled={@disabled}
      >
        Resign
      </button>
    </div>
    """
  end

  @doc "Status line under the board while guide mode is on."
  attr :piece, :string, default: nil, doc: "name of the selected piece, e.g. `Nb8`"
  attr :count, :integer, default: 0, doc: "number of legal moves for it"

  def guide_status(assigns) do
    ~H"""
    <p class="text-sm opacity-80" role="status" aria-live="polite">
      <%= if @piece do %>
        Guide on · {@count} {if @count == 1, do: "move", else: "moves"} for {@piece}
      <% else %>
        Guide on · select a piece to see its moves
      <% end %>
    </p>
    """
  end

  @doc "Shown to the player who received a draw offer."
  attr :from, :string, required: true
  attr :on_accept, :any, default: "accept_draw"
  attr :on_decline, :any, default: "decline_draw"

  def draw_offer(assigns) do
    ~H"""
    <div role="alert" class="alert alert-info alert-soft">
      <span><strong>{@from}</strong> offers a draw.</span>
      <div class="flex gap-2">
        <button type="button" class="btn btn-sm btn-primary" phx-click={@on_accept}>Accept</button>
        <button type="button" class="btn btn-sm" phx-click={@on_decline}>Decline</button>
      </div>
    </div>
    """
  end

  @doc "Banner announcing how a game, or one branch of it, ended."
  attr :reason, :atom,
    values: [
      :checkmate,
      :stalemate,
      :resignation,
      :agreed_draw,
      :repetition,
      :fifty_move,
      :timeout
    ],
    required: true

  attr :winner, :atom, values: [:white, :black, nil], default: nil
  attr :scope, :atom, values: [:game, :branch], default: :game

  def game_result(assigns) do
    ~H"""
    <div
      role="status"
      class={["alert", if(@winner, do: "alert-success", else: "alert-warning"), "alert-soft"]}
    >
      <div>
        <p class="font-semibold">{headline(@winner)}</p>
        <p class="text-sm opacity-80">
          {reason_text(@reason)}{if @scope == :branch,
            do: " · This branch is over; the game continues elsewhere."}
        </p>
      </div>
    </div>
    """
  end

  defp headline(nil), do: "Draw"
  defp headline(color), do: "#{color |> Atom.to_string() |> String.capitalize()} wins"

  defp reason_text(:checkmate), do: "Checkmate"
  defp reason_text(:stalemate), do: "Stalemate"
  defp reason_text(:resignation), do: "Resignation"
  defp reason_text(:agreed_draw), do: "Draw by agreement"
  defp reason_text(:repetition), do: "Threefold repetition"
  defp reason_text(:fifty_move), do: "Fifty-move rule"
  defp reason_text(:timeout), do: "Timeout"

  # ---------------------------------------------------------------------------
  # Branch overview
  # ---------------------------------------------------------------------------

  @step_x 64
  @step_y 56
  @pad_x 44
  @pad_y 36

  @doc """
  Git-style overview of every branch in a game.

  `nodes` are maps with `:id`, `:parent_id` (nil for the start position), `:ply`, `:san`,
  `:mover` (`:white`, `:black` or nil for the start) and optional `:status` (`:open`,
  `:checkmate`, `:stalemate`, `:resigned`, `:draw`). The first child of a node stays in its
  parent's lane, so the main line is the top lane and every further child opens a new lane.

  `cursors` marks where each player is looking, e.g. `%{white: "n3", black: "n5"}`.
  """
  attr :id, :string, default: "branch-graph"
  attr :nodes, :list, required: true
  attr :current, :string, default: nil, doc: "id of the node shown on the board"
  attr :cursors, :map, default: %{}
  attr :on_select, :any, default: nil, doc: "event name or JS command; sends `phx-value-id`"

  def branch_graph(assigns) do
    placed = layout(assigns.nodes)
    by_id = Map.new(placed, &{&1.id, &1})
    max_ply = placed |> Enum.map(& &1.ply) |> Enum.max(fn -> 0 end)
    lanes = placed |> Enum.map(& &1.lane) |> Enum.max(fn -> 0 end)

    assigns =
      assign(assigns,
        placed: placed,
        edges: for(n <- placed, n.parent_id, do: {n, by_id[n.parent_id]}),
        main_ids: main_line_ids(placed),
        width: @pad_x * 2 + max_ply * @step_x,
        height: @pad_y * 2 + lanes * @step_y
      )

    ~H"""
    <div class="overflow-x-auto rounded-box border border-base-300 bg-base-200 p-2">
      <svg
        id={@id}
        width={@width}
        height={@height}
        viewBox={"0 0 #{@width} #{@height}"}
        role="img"
        aria-label="Branch overview"
        class="mx-auto min-w-full"
      >
        <path
          :for={{node, parent} <- @edges}
          d={edge_path(parent, node)}
          fill="none"
          stroke-width={if node.id in @main_ids, do: 3, else: 2}
          class={if node.id in @main_ids, do: "stroke-primary", else: "stroke-base-content/40"}
        />
        <g
          :for={node <- @placed}
          transform={"translate(#{x(node)} #{y(node)})"}
          phx-click={@on_select}
          phx-value-id={node.id}
          class={@on_select && "cursor-pointer"}
        >
          <title>{node_title(node)}</title>
          <circle
            :if={node.id == @current}
            r="14"
            fill="none"
            stroke-width="2"
            class="stroke-accent"
          />
          <circle
            r="9"
            stroke-width="2"
            class={[
              "stroke-base-content",
              if(node.mover == :white, do: "fill-white", else: "fill-neutral")
            ]}
          />
          <text y="26" text-anchor="middle" font-size="11" class="fill-base-content font-mono">
            {node.san}
          </text>
          <text :if={badge(node)} x="18" y="4" font-size="13" font-weight="700" class="fill-error">
            {badge(node)}
          </text>
          <text
            :for={{color, i} <- cursor_colors(@cursors, node.id)}
            y={-16 - i * 12}
            text-anchor="middle"
            font-size="10"
            class="fill-accent font-semibold"
          >
            {cursor_label(color)}
          </text>
        </g>
      </svg>
    </div>
    """
  end

  @doc false
  def layout(nodes) do
    children = Enum.group_by(nodes, & &1.parent_id)

    case children[nil] do
      [root | _] ->
        {placed, _next_lane} = place(root, 0, children, %{}, 1)
        Enum.map(nodes, &Map.put(&1, :lane, Map.fetch!(placed, &1.id)))

      _ ->
        []
    end
  end

  defp place(node, lane, children, lanes, next_lane) do
    lanes = Map.put(lanes, node.id, lane)

    case Map.get(children, node.id, []) do
      [] ->
        {lanes, next_lane}

      [first | branches] ->
        {lanes, next_lane} = place(first, lane, children, lanes, next_lane)

        Enum.reduce(branches, {lanes, next_lane}, fn branch, {lanes, next_lane} ->
          place(branch, next_lane, children, lanes, next_lane + 1)
        end)
    end
  end

  defp main_line_ids(placed), do: for(n <- placed, n.lane == 0, into: MapSet.new(), do: n.id)

  defp x(node), do: @pad_x + node.ply * @step_x
  defp y(node), do: @pad_y + node.lane * @step_y

  defp edge_path(parent, node) when parent.lane == node.lane do
    "M#{x(parent)} #{y(parent)} L#{x(node)} #{y(node)}"
  end

  defp edge_path(parent, node) do
    mid = div(x(parent) + x(node), 2)
    "M#{x(parent)} #{y(parent)} C#{mid} #{y(parent)} #{mid} #{y(node)} #{x(node)} #{y(node)}"
  end

  defp node_title(%{mover: nil}), do: "Start position"

  defp node_title(node),
    do: "#{div(node.ply + 1, 2)}#{if node.mover == :black, do: "...", else: "."} #{node.san}"

  defp badge(%{status: :checkmate}), do: "#"
  defp badge(%{status: :stalemate}), do: "="
  defp badge(%{status: :draw}), do: "½"
  defp badge(%{status: :resigned}), do: "⚑"
  defp badge(_), do: nil

  defp cursor_colors(cursors, node_id) do
    cursors
    |> Enum.filter(fn {_color, id} -> id == node_id end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.with_index()
  end

  defp cursor_label(:white), do: "▽ W"
  defp cursor_label(:black), do: "▽ B"
end
