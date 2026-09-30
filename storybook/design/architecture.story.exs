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
    <div data-theme="light" class="prose prose-slate max-w-3xl space-y-4 p-6 text-slate-800">
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
    <div data-theme="light" class="max-w-4xl space-y-6 p-6">
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
    <div data-theme="light" class="max-w-6xl space-y-4 p-6">
      <div class="space-y-6">
        <section class="rounded-box border border-slate-300 bg-white p-4">
          <h3 class="mb-2 text-sm font-bold uppercase text-slate-600">Write side</h3>
          <div
            id="design-write-diagram"
            phx-hook="Mermaid"
            phx-update="ignore"
            class="flex justify-center overflow-x-auto"
          >
            {write_diagram()}
          </div>
        </section>
        <section class="rounded-box border border-slate-300 bg-white p-4">
          <h3 class="mb-2 text-sm font-bold uppercase text-slate-600">Read side</h3>
          <div
            id="design-read-diagram"
            phx-hook="Mermaid"
            phx-update="ignore"
            class="flex justify-center overflow-x-auto"
          >
            {read_diagram()}
          </div>
        </section>
      </div>
      <p class="text-xs text-slate-600">
        Rewind is a client-side view change and writes no events.
      </p>

      <ol class="list-decimal space-y-1 pl-6 text-sm text-slate-800">
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

  defp write_diagram do
    """
    flowchart TB
      lv[LiveView<br/>board + branch graph] --> cmd[Command<br/>MakeMove from_node_id]
      cmd --> router[Router<br/>Commanded dispatch]
      router --> agg[Game aggregate<br/>stream id = game id]
      agg <--> rules[Rules<br/>pure Elixir]
      agg --> events[Events<br/>MoveMade, BranchCreated,<br/>GameEnded]
      events --> store[(EventStore<br/>forkmate_eventstore)]
    """
  end

  defp read_diagram do
    """
    flowchart TB
      store[(EventStore)] --> proj[Projectors<br/>commanded_ecto_projections]
      proj --> repo[(Repo<br/>games, nodes, player_stats)]
      proj --> pubsub[PubSub<br/>game:id topic]
      pubsub --> lv[LiveView<br/>players + spectators]
      store -.-> timeout[Timeout manager]
      timeout -.->|ClaimTimeout| agg[Game aggregate]
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
