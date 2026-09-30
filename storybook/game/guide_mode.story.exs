defmodule ForkmateWeb.Storybook.Game.GuideMode do
  use PhoenixStorybook.Story, :page
  use Phoenix.Component

  import ForkmateWeb.GameComponents

  @queen_fen "4k3/8/8/8/3Q4/8/8/4K3 w - - 0 1"
  @queen_targets ~w(d1 d2 d3 d5 d6 d7 d8 a4 b4 c4 e4 f4 g4 h4 a1 b2 c3 e5 f6 g7 h8 a7 b6 c5 e3 f2 g1)

  def doc, do: "Guide mode: selecting a piece shows every square it can legally move to."

  def navigation do
    [
      {:overview, "Selecting a piece", {:local, "hero-cursor-arrow-rays"}},
      {:pieces, "Every piece", {:local, "hero-squares-2x2"}},
      {:rules, "Behaviour", {:local, "hero-clipboard-document-list"}}
    ]
  end

  def render(%{tab: :pieces} = assigns) do
    assigns = assign(assigns, :queen_targets, @queen_targets)

    ~H"""
    <div class="grid max-w-5xl gap-6 p-6 sm:grid-cols-2 lg:grid-cols-3">
      <.example title="Queen" note="Eight directions, every square until blocked.">
        <.board
          id="g-queen"
          guide
          fen="4k3/8/8/8/3Q4/8/8/4K3 w - - 0 1"
          selected="d4"
          targets={@queen_targets}
        />
      </.example>
      <.example title="Rook" note="Rank and file only.">
        <.board
          id="g-rook"
          guide
          fen="4k3/8/8/8/3R4/8/8/4K3 w - - 0 1"
          selected="d4"
          targets={~w(d1 d2 d3 d5 d6 d7 d8 a4 b4 c4 e4 f4 g4 h4)}
        />
      </.example>
      <.example title="Knight" note="Jumps, so squares are tinted but no direction lines.">
        <.board
          id="g-knight"
          guide
          fen="4k3/8/8/8/3N4/8/8/4K3 w - - 0 1"
          selected="d4"
          targets={~w(b3 b5 c2 c6 e2 e6 f3 f5)}
        />
      </.example>
      <.example title="Pawn" note="One or two squares from its start rank.">
        <.board id="g-pawn" guide selected="e2" targets={["e3", "e4"]} />
      </.example>
      <.example title="Castling" note="Shown on the king's destination squares.">
        <.board
          id="g-castle"
          guide
          fen="r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 6 8"
          selected="e1"
          targets={["c1", "g1"]}
        />
      </.example>
      <.example title="Promotion" note="Targets carry a queen badge.">
        <.board
          id="g-promo"
          guide
          fen="1n2k3/P7/8/8/8/8/8/4K3 w - - 0 1"
          selected="a7"
          targets={["a8", "b8"]}
          promotion_targets={["a8", "b8"]}
        />
      </.example>
      <.example title="Pinned piece" note="No legal moves, so nothing is highlighted.">
        <.board id="g-pin" guide fen="4r1k1/8/8/8/8/8/4B3/4K3 w - - 0 1" selected="e2" />
      </.example>
    </div>
    """
  end

  def render(%{tab: :rules} = assigns) do
    ~H"""
    <div class="prose max-w-3xl space-y-4 p-6">
      <h2>How guide mode behaves</h2>
      <ul>
        <li>Off by default. Off: selecting a piece shows nothing extra.</li>
        <li>
          On: click one of your pieces to select it. The square is tinted blue and every legal
          destination is shown.
        </li>
        <li>
          <strong>Green tint + dot:</strong>
          empty square it can move to. <strong>Red tint + ring:</strong>
          capture (including en passant).
        </li>
        <li>A green line runs along each straight direction to the farthest reachable square.</li>
        <li>Click a highlighted square to move; click the piece again or elsewhere to deselect.</li>
        <li>Clicking another of your own pieces switches the selection.</li>
        <li>
          Only the colour to move at the viewed node gets hints, so an opponent's pieces show none
          and rewinding shows branching options from that node.
        </li>
        <li>
          Targets always come from the Game aggregate. The board only draws them and never runs
          chess rules.
        </li>
      </ul>
    </div>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, queen_fen: @queen_fen, queen_targets: @queen_targets)

    ~H"""
    <div class="grid max-w-5xl gap-8 p-6 md:grid-cols-2">
      <div class="space-y-3">
        <h3 class="font-semibold">1. Guide off</h3>
        <.board id="ov-off" fen={@queen_fen} selected="d4" />
        <.game_controls />
        <p class="text-sm opacity-70">The piece is selected but no moves are revealed.</p>
      </div>
      <div class="space-y-3">
        <h3 class="font-semibold">2. Guide on, queen selected</h3>
        <.board id="ov-on" guide fen={@queen_fen} selected="d4" targets={@queen_targets} />
        <.game_controls guide />
        <.guide_status piece="Qd4" count={length(@queen_targets)} />
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :note, :string, required: true
  slot :inner_block, required: true

  defp example(assigns) do
    ~H"""
    <figure class="space-y-2">
      {render_slot(@inner_block)}
      <figcaption>
        <div class="font-semibold">{@title}</div>
        <div class="text-sm opacity-70">{@note}</div>
      </figcaption>
    </figure>
    """
  end
end
