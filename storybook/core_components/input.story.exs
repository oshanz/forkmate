defmodule ForkmateWeb.Storybook.CoreComponents.Input do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.CoreComponents.input/1

  def variations do
    [
      %Variation{
        id: :text,
        attributes: %{type: "text", name: "name", label: "Name", value: "Magnus"}
      },
      %Variation{
        id: :select,
        attributes: %{
          type: "select",
          name: "level",
          label: "Level",
          value: "medium",
          options: [Easy: "easy", Medium: "medium", Hard: "hard", Max: "max"]
        }
      },
      %Variation{
        id: :checkbox,
        attributes: %{type: "checkbox", name: "guide", label: "Guide mode", checked: true}
      },
      %Variation{
        id: :textarea,
        attributes: %{type: "textarea", name: "note", label: "Note", value: "Nice game"}
      },
      %Variation{
        id: :errors,
        attributes: %{
          type: "text",
          name: "email",
          label: "Email",
          value: "nope",
          errors: ["is invalid"]
        }
      }
    ]
  end
end
