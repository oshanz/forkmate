defmodule ForkmateWeb.Storybook.Game.BranchPanel do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.branch_panel/1

  def container, do: {:div, class: "flex h-[28rem] max-w-md flex-col"}

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

  # A long main line with side branches, to show the graph scrolling.
  @long for ply <- 1..24,
            do: %{
              id: "m#{ply}",
              parent_id: if(ply == 1, do: "n0", else: "m#{ply - 1}"),
              ply: ply,
              san: "m#{ply}",
              mover: if(rem(ply, 2) == 1, do: :white, else: :black)
            }

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{id: "panel-default", nodes: @nodes, current: "n5"}
      },
      %Variation{
        id: :overflowing,
        description: "More nodes than fit; the graph scrolls inside the panel",
        attributes: %{
          id: "panel-long",
          nodes: [hd(@nodes) | @long],
          current: "m24",
          cursors: %{white: "m24", black: "m10"}
        }
      }
    ]
  end
end
