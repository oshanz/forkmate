defmodule ForkmateWeb.Storybook.Design.GameScreen do
  use PhoenixStorybook.Story, :page
  use Phoenix.Component

  import ForkmateWeb.GameComponents

  def doc, do: "The game page composed from the game components, with sample data."

  def navigation do
    [
      {:playing, "Playing", {:local, "hero-play"}},
      {:finished, "Finished", {:local, "hero-flag"}}
    ]
  end

  @fen "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"

  def render(assigns) do
    assigns =
      assign(assigns,
        fen: @fen,
        moves: moves(),
        nodes: nodes(),
        finished?: assigns[:tab] == :finished
      )

    ~H"""
    <div class="grid max-w-6xl gap-6 p-6 lg:grid-cols-[minmax(0,32rem)_1fr]">
      <section class="space-y-2">
        <.player_card name="Magnus" rating={2830} color={:black} active={!@finished?} seconds={287} />
        <.board id="screen-board" fen={@fen} last_move={{"f1", "b5"}} />
        <.player_card name="Hikaru" rating={2795} color={:white} seconds={301} />
        <.game_result :if={@finished?} reason={:checkmate} winner={:white} />
        <.draw_offer :if={!@finished?} from="Hikaru" />
        <.game_controls disabled={@finished?} />
      </section>

      <aside class="space-y-4">
        <div>
          <h3 class="mb-1 font-semibold">Moves</h3>
          <div class="rounded-box border border-base-300 bg-base-200 p-2">
            <.move_list moves={@moves} current="n5" forks={["n1", "n2"]} />
          </div>
        </div>
        <div>
          <h3 class="mb-1 font-semibold">Branches</h3>
          <.branch_graph
            id="screen-branches"
            nodes={@nodes}
            current="n5"
            cursors={%{white: "n5", black: "n5"}}
          />
        </div>
      </aside>
    </div>
    """
  end

  defp moves do
    [
      %{id: "n1", ply: 1, san: "e4"},
      %{id: "n2", ply: 2, san: "e5"},
      %{id: "n3", ply: 3, san: "Nf3"},
      %{id: "n4", ply: 4, san: "Nc6"},
      %{id: "n5", ply: 5, san: "Bb5"}
    ]
  end

  defp nodes do
    [
      %{id: "n0", parent_id: nil, ply: 0, san: "start", mover: nil},
      %{id: "n1", parent_id: "n0", ply: 1, san: "e4", mover: :white},
      %{id: "n2", parent_id: "n1", ply: 2, san: "e5", mover: :black},
      %{id: "n3", parent_id: "n2", ply: 3, san: "Nf3", mover: :white},
      %{id: "n4", parent_id: "n3", ply: 4, san: "Nc6", mover: :black},
      %{id: "n5", parent_id: "n4", ply: 5, san: "Bb5", mover: :white},
      %{id: "n6", parent_id: "n1", ply: 2, san: "c5", mover: :black}
    ]
  end
end
