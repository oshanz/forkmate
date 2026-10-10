defmodule ForkmateWeb.Storybook.CoreComponents.Table do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.table/1

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          id: "games",
          rows: [
            %{id: 1, white: "You", black: "Stockfish (easy)", status: "open"},
            %{id: 2, white: "Stockfish (hard)", black: "You", status: "ended"}
          ]
        },
        slots: [
          ~s(<:col :let={g} label="White">{g.white}</:col>),
          ~s(<:col :let={g} label="Black">{g.black}</:col>),
          ~s(<:col :let={g} label="Status">{g.status}</:col>),
          ~s(<:action :let={g}><a class="link" href="#">Open {g.id}</a></:action>)
        ]
      }
    ]
  end
end
