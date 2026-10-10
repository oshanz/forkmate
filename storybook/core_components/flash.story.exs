defmodule ForkmateWeb.Storybook.CoreComponents.Flash do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.flash/1

  def variations do
    [
      %Variation{id: :info, attributes: %{kind: :info}, slots: ["Game saved."]},
      %Variation{
        id: :info_title,
        attributes: %{kind: :info, title: "Success!"},
        slots: ["Your move was played."]
      },
      %Variation{
        id: :error,
        attributes: %{kind: :error, title: "Error!"},
        slots: ["That move is not legal."]
      }
    ]
  end
end
