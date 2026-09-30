defmodule ForkmateWeb.Storybook.Game.BranchGraph do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.branch_graph/1

  # The example from docs/design-brainstorm.md. The first child of a node stays on
  # its lane, so the main line is the top lane and each later child opens a lane.
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

  @finished [
    %{id: "a0", parent_id: nil, ply: 0, san: "start", mover: nil},
    %{id: "a1", parent_id: "a0", ply: 1, san: "f3", mover: :white},
    %{id: "a2", parent_id: "a1", ply: 2, san: "e5", mover: :black},
    %{id: "a3", parent_id: "a2", ply: 3, san: "g4", mover: :white},
    %{id: "a4", parent_id: "a3", ply: 4, san: "Qh4#", mover: :black, status: :checkmate},
    %{id: "a5", parent_id: "a2", ply: 3, san: "e4", mover: :white, status: :resigned},
    %{id: "a6", parent_id: "a1", ply: 2, san: "d5", mover: :black, status: :draw}
  ]

  def variations do
    [
      %Variation{
        id: :overview,
        description: "Main line on top, one lane per branch",
        attributes: %{nodes: @nodes, current: "n5"}
      },
      %Variation{
        id: :cursors,
        description: "Each player's current position, and a node previewed after rewinding",
        attributes: %{nodes: @nodes, current: "n3", cursors: %{white: "n3", black: "n7"}}
      },
      %Variation{
        id: :results,
        description: "Branch tips show how each line ended: mate #, resigned ⚑, draw ½",
        attributes: %{nodes: @finished, current: "a4"}
      },
      %Variation{
        id: :start_only,
        attributes: %{
          nodes: [%{id: "s", parent_id: nil, ply: 0, san: "start", mover: nil}],
          current: "s"
        }
      }
    ]
  end
end
