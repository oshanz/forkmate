defmodule ForkmateWeb.Storybook.Game.Birdview do
  use PhoenixStorybook.Story, :component

  # Bird view is `branch_graph/1` with `birdview` on: every node is a small board.
  def function, do: &ForkmateWeb.GameComponents.branch_graph/1

  # Same tree as the branch graph story.
  @nodes [
    %{id: "n0", parent_id: nil, ply: 0, san: "start", mover: nil},
    %{id: "n1", parent_id: "n0", ply: 1, san: "e4", mover: :white},
    %{id: "n2", parent_id: "n1", ply: 2, san: "e5", mover: :black},
    %{id: "n3", parent_id: "n2", ply: 3, san: "Nf3", mover: :white},
    %{id: "n4", parent_id: "n3", ply: 4, san: "Nc6", mover: :black},
    %{id: "n5", parent_id: "n4", ply: 5, san: "Bb5", mover: :white},
    %{id: "n6", parent_id: "n1", ply: 2, san: "c5", mover: :black},
    %{id: "n7", parent_id: "n6", ply: 3, san: "Nf3", mover: :white},
    %{id: "n8", parent_id: "n0", ply: 1, san: "d4", mover: :white},
    %{id: "n9", parent_id: "n8", ply: 2, san: "d5", mover: :black}
  ]

  # Positions along the tree above, so bird view has boards to draw.
  @fens %{
    "n0" => "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    "n1" => "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
    "n2" => "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
    "n3" => "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
    "n4" => "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
    "n5" => "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
    "n6" => "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
    "n7" => "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
    "n8" => "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
    "n9" => "rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2"
  }

  # The move that led to each node; birdview highlights its from and to squares.
  @last_moves %{
    "n1" => {"e2", "e4"},
    "n2" => {"e7", "e5"},
    "n3" => {"g1", "f3"},
    "n4" => {"b8", "c6"},
    "n5" => {"f1", "b5"},
    "n6" => {"c7", "c5"},
    "n7" => {"g1", "f3"},
    "n8" => {"d2", "d4"},
    "n9" => {"d7", "d5"}
  }

  @bird_nodes Enum.map(
                @nodes,
                &Map.merge(&1, %{fen: Map.fetch!(@fens, &1.id), last_move: @last_moves[&1.id]})
              )

  def variations do
    [
      %Variation{
        id: :birdview,
        description: "Every node drawn as a small board instead of a dot",
        attributes: %{nodes: @bird_nodes, current: "n5", birdview: true}
      },
      %Variation{
        id: :cursors,
        description: "Keeps the current-node ring and both players' cursors",
        attributes: %{
          nodes: @bird_nodes,
          current: "n3",
          cursors: %{white: "n3", black: "n7"},
          birdview: true
        }
      }
    ]
  end
end
