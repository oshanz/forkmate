defmodule ForkmateWeb.Storybook.Design.Architecture do
  use PhoenixStorybook.Story, :page
  use Phoenix.Component

  import ForkmateWeb.GameComponents

  def doc, do: "CQRS / event-sourcing design for Forkmate, drawn from docs/design-brainstorm.md."

  def navigation do
    [
      {:flow, "Command & event flow", {:local, "hero-arrows-right-left"}},
      {:branching, "Branching model", {:local, "hero-share"}},
      {:aggregates, "Commands & events", {:local, "hero-table-cells"}}
    ]
  end

  def render(%{tab: :branching} = assigns) do
    assigns = assign(assigns, :nodes, nodes())

    ~H"""
    <div class="prose max-w-3xl space-y-4 p-6">
      <h2>A game is a tree of positions</h2>
      <p>
        Rewinding is client-side and writes nothing. Playing a different move from an earlier
        node whose colour is to move appends <code>MoveMade</code> and <code>BranchCreated</code>.
        The first child stays on the parent's lane, every later child opens a new lane.
      </p>
      <.branch_graph
        id="design-branch-graph"
        nodes={@nodes}
        current="n5"
        cursors={%{white: "n5", black: "n7"}}
      />
      <ul>
        <li><strong>Blue line:</strong> main line (top lane).</li>
        <li><strong>White / dark dots:</strong> which colour made the move.</li>
        <li>
          <strong>▽ W / ▽ B:</strong> where each player is looking (Presence or LiveView cursor).
        </li>
        <li><strong>Badges:</strong> # mate, = stalemate, ½ draw, ⚑ resigned.</li>
      </ul>
    </div>
    """
  end

  def render(%{tab: :aggregates} = assigns) do
    ~H"""
    <div class="max-w-4xl space-y-6 p-6">
      <table class="table table-zebra">
        <thead>
          <tr>
            <th>Command</th>
            <th>Events</th>
            <th>Rejected when</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{c, e, r} <- rows()}>
            <td class="font-mono text-sm">{c}</td>
            <td class="font-mono text-sm">{e}</td>
            <td class="text-sm">{r}</td>
          </tr>
        </tbody>
      </table>
      <p class="text-sm text-base-content/70">
        Separate aggregates: <code>Player</code>, <code>Challenge</code>/<code>Lobby</code>, <code>Tournament</code>. Keep them out of
        <code>Game</code>
        so its stream stays small.
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-6xl space-y-4 p-6">
      <svg viewBox="0 0 1000 410" role="img" aria-label="Command and event flow" class="w-full">
        <defs>
          <marker
            id="arrow"
            viewBox="0 0 10 10"
            refX="9"
            refY="5"
            markerWidth="7"
            markerHeight="7"
            orient="auto-start-reverse"
          >
            <path d="M0 0 L10 5 L0 10 z" class="fill-base-content/70" />
          </marker>
        </defs>

        <text x="20" y="28" font-size="13" font-weight="700" class="fill-base-content/60">
          WRITE SIDE
        </text>
        <text x="20" y="268" font-size="13" font-weight="700" class="fill-base-content/60">
          READ SIDE
        </text>
        <line
          x1="20"
          x2="980"
          y1="248"
          y2="248"
          stroke-dasharray="5 5"
          class="stroke-base-content/30"
        />

        <.box x="20" y="50" w="150" title="LiveView" sub="board + branch graph" tone="primary" />
        <.box x="230" y="50" w="140" title="Command" sub="MakeMove {from_node_id}" />
        <.box x="430" y="50" w="140" title="Router" sub="Commanded dispatch" />
        <.box
          x="630"
          y="40"
          w="170"
          h="100"
          title="Game aggregate"
          sub="one per game · stream id = game id"
          tone="accent"
        />
        <.box x="860" y="50" w="120" title="Rules" sub="pure Elixir module" />

        <.arrow d="M170 80 H230" />
        <.arrow d="M370 80 H430" />
        <.arrow d="M570 80 H630" />
        <.arrow d="M800 80 H860" />

        <.box x="630" y="180" w="170" title="Events" sub="MoveMade · BranchCreated · GameEnded" />
        <.arrow d="M715 140 V180" />

        <.box
          x="430"
          y="180"
          w="140"
          title="EventStore"
          sub="Postgres · forkmate_eventstore"
          tone="neutral"
        />
        <.arrow d="M630 210 H570" />

        <.box x="430" y="290" w="140" title="Projectors" sub="commanded_ecto_projections" />
        <.box
          x="630"
          y="290"
          w="140"
          title="Repo"
          sub="games · nodes · player_stats"
          tone="neutral"
        />
        <.box x="230" y="290" w="140" title="PubSub" sub="game:{id} topic" />
        <.box x="20" y="290" w="150" title="LiveView" sub="players + spectators" tone="primary" />
        <.box x="830" y="290" w="150" title="Timeout manager" sub="dispatches ClaimTimeout" />

        <.arrow d="M500 240 V290" />
        <.arrow d="M570 320 H630" />
        <.arrow d="M430 320 H370" />
        <.arrow d="M230 320 H170" />
        <.arrow d="M905 290 V210 H800" dashed />

        <text x="20" y="390" font-size="12" class="fill-base-content/70">
          Rewind is a client-side view change and writes no events.
        </text>
      </svg>

      <ol class="list-decimal space-y-1 pl-6 text-sm">
        <li>The player's move becomes <code>MakeMove</code> with the node it starts from.</li>
        <li>The aggregate asks the rules module, then emits events carrying SAN, FEN and clocks.</li>
        <li>
          Projectors build <code>nodes</code>
          and <code>games</code>; PubSub pushes the update to both players and spectators.
        </li>
        <li>
          A process manager turns clock expiry into <code>ClaimTimeout</code>, which the aggregate validates.
        </li>
      </ol>
    </div>
    """
  end

  attr :x, :string, required: true
  attr :y, :string, required: true
  attr :w, :string, default: "140"
  attr :h, :string, default: "60"
  attr :title, :string, required: true
  attr :sub, :string, default: nil
  attr :tone, :string, default: "base"

  defp box(assigns) do
    ~H"""
    <g transform={"translate(#{@x} #{@y})"}>
      <rect
        width={@w}
        height={@h}
        rx="8"
        stroke-width="1.5"
        class={
          case @tone do
            "primary" -> "fill-primary/15 stroke-primary"
            "accent" -> "fill-accent/15 stroke-accent"
            "neutral" -> "fill-neutral/20 stroke-neutral"
            _ -> "fill-base-200 stroke-base-content/40"
          end
        }
      />
      <text
        x={String.to_integer(@w) / 2}
        y="24"
        text-anchor="middle"
        font-size="14"
        font-weight="600"
        class="fill-base-content"
      >
        {@title}
      </text>
      <text
        :if={@sub}
        x={String.to_integer(@w) / 2}
        y="43"
        text-anchor="middle"
        font-size="10"
        class="fill-base-content/70"
      >
        {@sub}
      </text>
    </g>
    """
  end

  attr :d, :string, required: true
  attr :dashed, :boolean, default: false

  defp arrow(assigns) do
    ~H"""
    <path
      d={@d}
      fill="none"
      stroke-width="1.75"
      marker-end="url(#arrow)"
      stroke-dasharray={@dashed && "5 4"}
      class="stroke-base-content/70"
    />
    """
  end

  defp nodes do
    [
      %{id: "n0", parent_id: nil, ply: 0, san: "start", mover: nil},
      %{id: "n1", parent_id: "n0", ply: 1, san: "e4", mover: :white},
      %{id: "n2", parent_id: "n1", ply: 2, san: "e5", mover: :black},
      %{id: "n3", parent_id: "n2", ply: 3, san: "Nf3", mover: :white},
      %{id: "n4", parent_id: "n3", ply: 4, san: "Nc6", mover: :black},
      %{id: "n5", parent_id: "n4", ply: 5, san: "Bb5", mover: :white},
      %{id: "n6", parent_id: "n1", ply: 2, san: "c5", mover: :black},
      %{id: "n7", parent_id: "n6", ply: 3, san: "Nf3", mover: :white},
      %{id: "n8", parent_id: "n0", ply: 1, san: "d4", mover: :white},
      %{id: "n9", parent_id: "n8", ply: 2, san: "d5", mover: :black, status: :draw}
    ]
  end

  defp rows do
    [
      {"StartGame", "GameStarted", "game already exists"},
      {"MakeMove", "MoveMade, BranchCreated, CheckDeclared, GameEnded",
       "unknown node, not your colour to move there, illegal move, node ended"},
      {"Resign", "GameEnded (resignation)", "game over"},
      {"OfferDraw / AcceptDraw / DeclineDraw", "DrawOffered, GameEnded, DrawDeclined",
       "no open offer, own offer"},
      {"ClaimTimeout", "GameEnded (timeout)", "opponent still has time"},
      {"ClaimDraw", "GameEnded (repetition / fifty-move)", "condition not met"}
    ]
  end
end
