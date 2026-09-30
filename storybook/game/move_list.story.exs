defmodule ForkmateWeb.Storybook.Game.MoveList do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.move_list/1

  def container, do: {:div, class: "max-w-xs"}

  @moves [
    %{id: "n1", ply: 1, san: "e4"},
    %{id: "n2", ply: 2, san: "e5"},
    %{id: "n3", ply: 3, san: "Nf3"},
    %{id: "n4", ply: 4, san: "Nc6"},
    %{id: "n5", ply: 5, san: "Bb5"}
  ]

  def variations do
    [
      %Variation{
        id: :latest,
        description: "Viewing the latest move; an odd ply leaves the last row half empty",
        attributes: %{moves: @moves, current: "n5"}
      },
      %Variation{
        id: :rewound,
        description: "Rewound to 2.Nf3, which has a sibling branch",
        attributes: %{moves: @moves, current: "n3", forks: ["n2", "n3"]}
      }
    ]
  end
end
