defmodule ForkmateWeb.Storybook.Game.Board do
  use PhoenixStorybook.Story, :component

  def function, do: &ForkmateWeb.GameComponents.board/1

  def container, do: {:div, class: "max-w-md"}

  def variations do
    [
      %Variation{id: :start, description: "Start position, white at the bottom"},
      %Variation{
        id: :black_view,
        description: "Same position seen from black's side",
        attributes: %{orientation: :black}
      },
      %Variation{
        id: :last_move,
        description: "After 1.e4 e5 2.Nf3, with the last move highlighted",
        attributes: %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          last_move: {"g1", "f3"}
        }
      },
      %Variation{
        id: :selected,
        description: "A piece is selected and its legal targets are shown",
        attributes: %{
          fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
          selected: "b8",
          targets: ["a6", "c6"]
        }
      },
      %Variation{
        id: :capture_targets,
        description: "Capture targets get a ring instead of a dot",
        attributes: %{
          fen: "rnbqkbnr/ppp2ppp/8/3pp3/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3",
          selected: "e4",
          targets: ["d5"]
        }
      },
      %Variation{
        id: :check,
        description: "King in check after Bb5+",
        attributes: %{
          fen: "rnbqkbnr/ppp2ppp/8/1B1pp3/4P3/8/PPPP1PPP/RNBQK1NR b KQkq - 1 3",
          check: "e8",
          last_move: {"f1", "b5"}
        }
      }
    ]
  end
end
