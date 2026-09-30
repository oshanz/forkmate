defmodule ForkmateWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ForkmateWeb.GameComponents

  test "board shows a queen badge on promotion targets" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameComponents.board
        fen="1n2k3/P7/8/8/8/8/8/4K3 w - - 0 1"
        selected="a7"
        targets={["a8", "b8"]}
        promotion_targets={["a8", "b8"]}
      />
      """)

    assert length(String.split(html, "♛")) - 1 == 2
  end

  test "guide mode tints targets and draws one line per straight direction" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameComponents.board
        guide
        fen="4k3/8/8/8/3Q4/8/8/4K3 w - - 0 1"
        selected="d4"
        targets={~w(d5 d8 a4 h4 a1 g1 e5 h8)}
      />
      """)

    assert length(String.split(html, "<line")) - 1 == 6
    assert length(String.split(html, ~s(fill="#48bb78"))) - 1 == 8
  end

  test "guide mode draws no lines for knight jumps" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameComponents.board guide selected="b1" targets={["a3", "c3"]} />
      """)

    refute html =~ "<line"
  end

  test "game_controls reflects guide state" do
    assigns = %{}

    off = rendered_to_string(~H"<GameComponents.game_controls />")
    on = rendered_to_string(~H"<GameComponents.game_controls guide />")

    assert off =~ "Guide off"
    assert on =~ "Guide on"
    assert on =~ ~s(aria-pressed="true")
  end

  test "guide_status pluralises" do
    assigns = %{}

    assert rendered_to_string(~H'<GameComponents.guide_status piece="Nb8" count={2} />') =~
             "2 moves for Nb8"

    assert rendered_to_string(~H'<GameComponents.guide_status piece="Ke1" count={1} />') =~
             "1 move for Ke1"
  end

  describe "branch_graph birdview" do
    @nodes [
      %{
        id: "n0",
        parent_id: nil,
        ply: 0,
        san: "start",
        mover: nil,
        fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
      },
      %{
        id: "n1",
        parent_id: "n0",
        ply: 1,
        san: "e4",
        mover: :white,
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
      },
      %{id: "n2", parent_id: "n0", ply: 1, san: "d4", mover: :white}
    ]

    test "draws dots by default" do
      assigns = %{nodes: @nodes}

      html = rendered_to_string(~H"<GameComponents.branch_graph nodes={@nodes} />")

      assert html =~ "<circle"
      refute html =~ "branch-graph-board-"
    end

    test "draws a board per node with a fen and keeps a dot for the rest" do
      assigns = %{nodes: @nodes}

      html = rendered_to_string(~H"<GameComponents.branch_graph nodes={@nodes} birdview />")

      assert html =~ ~s(id="branch-graph-board-n0")
      assert html =~ ~s(id="branch-graph-board-n1")
      refute html =~ ~s(id="branch-graph-board-n2")
      assert length(String.split(html, "<circle")) - 1 == 1
    end

    test "marks the piece that moved as selected" do
      nodes = [
        %{
          id: "n0",
          parent_id: nil,
          ply: 0,
          san: "start",
          mover: nil,
          fen: "8/8/8/8/8/8/8/8 w - - 0 1"
        },
        %{
          id: "n1",
          parent_id: "n0",
          ply: 1,
          san: "e4",
          mover: :white,
          fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
          last_move: {"e2", "e4"}
        }
      ]

      assigns = %{nodes: nodes}

      html = rendered_to_string(~H"<GameComponents.branch_graph nodes={@nodes} birdview />")

      assert length(String.split(html, ~s(fill="#63b3ed"))) - 1 == 1
    end

    test "toggle reflects its state" do
      assigns = %{}

      html = rendered_to_string(~H"<GameComponents.birdview_toggle on />")

      assert html =~ ~s(aria-checked="true")
    end
  end
end
