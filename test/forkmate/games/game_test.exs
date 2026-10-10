defmodule Forkmate.Games.GameTest do
  use ExUnit.Case, async: true

  alias Forkmate.Games.Commands.{AcceptDraw, DeclineDraw, MakeMove, OfferDraw, Resign, StartGame}

  alias Forkmate.Games.Events.{
    BranchCreated,
    DrawDeclined,
    DrawOffered,
    GameEnded,
    GameStarted,
    MoveMade
  }

  alias Forkmate.Games.Game

  @game_id "game-1"
  @white "player-w"
  @black "player-b"

  describe "StartGame" do
    test "starts a new game from initial position" do
      game = %Game{}
      cmd = %StartGame{game_id: @game_id, white_player_id: @white, black_player_id: @black}

      assert {:ok, [%GameStarted{} = event]} = Game.execute(game, cmd)
      assert event.game_id == @game_id
      assert event.white_player_id == @white
      assert event.black_player_id == @black
      assert is_binary(event.root_node_id)

      # Test apply
      game = Game.apply(game, event)
      assert game.game_status == :active
      assert Map.has_key?(game.nodes, event.root_node_id)
      root = game.nodes[event.root_node_id]
      assert root.ply == 0
      assert root.status == :open
    end

    test "cannot start an already started game" do
      game = %Game{}
      cmd = %StartGame{game_id: @game_id, white_player_id: @white, black_player_id: @black}
      {:ok, [event]} = Game.execute(game, cmd)
      game = Game.apply(game, event)

      assert {:error, :game_already_started} = Game.execute(game, cmd)
    end
  end

  describe "MakeMove" do
    setup do
      game = %Game{}
      cmd = %StartGame{game_id: @game_id, white_player_id: @white, black_player_id: @black}
      {:ok, [event]} = Game.execute(game, cmd)
      game = Game.apply(game, event)
      [game: game, root_id: event.root_node_id]
    end

    test "white plays e4 from root", %{game: game, root_id: root_id} do
      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "e2",
        to: "e4",
        player_id: @white
      }

      assert {:ok, [%MoveMade{} = move_event]} = Game.execute(game, cmd)
      assert move_event.san == "e4"
      assert move_event.parent_node_id == root_id
      assert move_event.ply == 1
      assert move_event.mover == :white

      game = Game.apply(game, move_event)
      assert Map.has_key?(game.nodes, move_event.node_id)
      assert root_id in Map.keys(game.nodes)
      assert game.nodes[root_id].children == [move_event.node_id]
    end

    test "rejects move if not player's turn", %{game: game, root_id: root_id} do
      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "e7",
        to: "e5",
        player_id: @black
      }

      assert {:error, :not_your_turn} = Game.execute(game, cmd)
    end

    test "rejects illegal move", %{game: game, root_id: root_id} do
      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "e2",
        to: "e5",
        player_id: @white
      }

      assert {:error, :illegal_move} = Game.execute(game, cmd)
    end

    test "branching: playing an alternative move from root creates a branch", %{
      game: game,
      root_id: root_id
    } do
      # 1. White plays e4 (main line move)
      cmd1 = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "e2",
        to: "e4",
        player_id: @white
      }

      {:ok, [%MoveMade{} = move1]} = Game.execute(game, cmd1)
      game = Game.apply(game, move1)

      # 2. White now also branches from root with d4!
      cmd2 = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "d2",
        to: "d4",
        player_id: @white
      }

      assert {:ok, [%BranchCreated{} = branch_event, %MoveMade{} = move2]} =
               Game.execute(game, cmd2)

      assert branch_event.parent_node_id == root_id
      assert branch_event.node_id == move2.node_id
      assert move2.san == "d4"

      game = game |> Game.apply(branch_event) |> Game.apply(move2)

      # Root now has two children: move1 and move2
      root = game.nodes[root_id]
      assert length(root.children) == 2
      assert move1.node_id in root.children
      assert move2.node_id in root.children

      # Black can respond on either branch:
      # e.g. Black responds to move1 (e4) with c5
      cmd_black_e4 = %MakeMove{
        game_id: @game_id,
        from_node_id: move1.node_id,
        from: "c7",
        to: "c5",
        player_id: @black
      }

      assert {:ok, [%MoveMade{} = black_move1]} = Game.execute(game, cmd_black_e4)
      assert black_move1.san == "c5"

      # Or Black responds to move2 (d4) with d5
      cmd_black_d4 = %MakeMove{
        game_id: @game_id,
        from_node_id: move2.node_id,
        from: "d7",
        to: "d5",
        player_id: @black
      }

      assert {:ok, [%MoveMade{} = black_move2]} = Game.execute(game, cmd_black_d4)
      assert black_move2.san == "d5"
    end

    test "checkmate ends branch and marks node ended", %{game: game, root_id: root_id} do
      # Play fool's mate: 1. f3 e5 2. g4 Qh4#
      {:ok, [m1]} =
        Game.execute(game, %MakeMove{
          game_id: @game_id,
          from_node_id: root_id,
          from: "f2",
          to: "f3",
          player_id: @white
        })

      game = Game.apply(game, m1)

      {:ok, [m2]} =
        Game.execute(game, %MakeMove{
          game_id: @game_id,
          from_node_id: m1.node_id,
          from: "e7",
          to: "e5",
          player_id: @black
        })

      game = Game.apply(game, m2)

      {:ok, [m3]} =
        Game.execute(game, %MakeMove{
          game_id: @game_id,
          from_node_id: m2.node_id,
          from: "g2",
          to: "g4",
          player_id: @white
        })

      game = Game.apply(game, m3)

      {:ok, [m4, end_event]} =
        Game.execute(game, %MakeMove{
          game_id: @game_id,
          from_node_id: m3.node_id,
          from: "d8",
          to: "h4",
          player_id: @black
        })

      assert m4.san == "Qh4#"
      assert m4.is_checkmate
      assert %GameEnded{reason: :checkmate, winner: :black, scope: :branch} = end_event

      game = game |> Game.apply(m4) |> Game.apply(end_event)
      assert game.nodes[m4.node_id].status == :checkmate

      # Attempting to move from this ended node is rejected
      cmd_after = %MakeMove{
        game_id: @game_id,
        from_node_id: m4.node_id,
        from: "e1",
        to: "f2",
        player_id: @white
      }

      assert {:error, :node_already_ended} = Game.execute(game, cmd_after)
    end
  end

  describe "Resignation and Draws" do
    setup do
      game = %Game{}
      cmd = %StartGame{game_id: @game_id, white_player_id: @white, black_player_id: @black}
      {:ok, [event]} = Game.execute(game, cmd)
      [game: Game.apply(game, event)]
    end

    test "resignation ends the whole game", %{game: game} do
      assert {:ok, [%GameEnded{} = end_event]} =
               Game.execute(game, %Resign{game_id: @game_id, player_id: @white})

      assert end_event.reason == :resignation
      assert end_event.winner == :black
      assert end_event.scope == :game

      game = Game.apply(game, end_event)
      assert game.game_status == :ended

      assert {:error, :game_ended} =
               Game.execute(game, %Resign{game_id: @game_id, player_id: @black})
    end

    test "draw offer and acceptance", %{game: game} do
      assert {:ok, [%DrawOffered{}]} =
               Game.execute(game, %OfferDraw{game_id: @game_id, player_id: @white})

      game = Game.apply(game, %DrawOffered{game_id: @game_id, player_id: @white})
      assert game.draw_offered_by == @white

      # Opponent accepts
      assert {:ok, [%GameEnded{reason: :agreed_draw, scope: :game}]} =
               Game.execute(game, %AcceptDraw{game_id: @game_id, player_id: @black})
    end

    test "draw offer and decline", %{game: game} do
      game = Game.apply(game, %DrawOffered{game_id: @game_id, player_id: @white})

      assert {:ok, [%DrawDeclined{}]} =
               Game.execute(game, %DeclineDraw{game_id: @game_id, player_id: @black})

      game = Game.apply(game, %DrawDeclined{game_id: @game_id, player_id: @black})
      assert game.draw_offered_by == nil
    end

    test "cannot accept own draw offer", %{game: game} do
      game = Game.apply(game, %DrawOffered{game_id: @game_id, player_id: @white})

      assert {:error, :cannot_accept_own_draw_offer} =
               Game.execute(game, %AcceptDraw{game_id: @game_id, player_id: @white})
    end
  end

  describe "replay from the event store" do
    defp roundtrip(%module{} = event) do
      serialized = EventStore.JsonSerializer.serialize(event)
      EventStore.JsonSerializer.deserialize(serialized, type: Atom.to_string(module))
    end

    defp start_game_state do
      cmd = %StartGame{game_id: @game_id, white_player_id: @white, black_player_id: @black}
      {:ok, [started]} = Game.execute(%Game{}, cmd)
      {Game.apply(%Game{}, started), started.root_node_id}
    end

    test "applies JSON-deserialized MoveMade events" do
      {game, root_id} = start_game_state()

      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "e2",
        to: "e4",
        player_id: @white
      }

      {:ok, [move]} = Game.execute(game, cmd)
      game = Game.apply(game, roundtrip(move))

      assert game.nodes[move.node_id].mover == :white
    end

    test "applies JSON-deserialized game-level GameEnded events" do
      {game, _root_id} = start_game_state()

      {:ok, [ended]} = Game.execute(game, %Resign{game_id: @game_id, player_id: @white})
      game = Game.apply(game, roundtrip(ended))

      assert game.game_status == :ended
    end

    test "applies JSON-deserialized branch-level GameEnded events" do
      {game, root_id} = start_game_state()

      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "e2",
        to: "e4",
        player_id: @white
      }

      {:ok, [move]} = Game.execute(game, cmd)
      game = Game.apply(game, move)

      ended = %GameEnded{
        game_id: @game_id,
        node_id: move.node_id,
        reason: :checkmate,
        winner: :white,
        scope: :branch
      }

      game = Game.apply(game, roundtrip(ended))

      assert game.nodes[move.node_id].status == :checkmate
    end
  end

  describe "MakeMove input validation" do
    setup do
      cmd = %StartGame{game_id: @game_id, white_player_id: @white, black_player_id: @black}
      {:ok, [event]} = Game.execute(%Game{}, cmd)
      [game: Game.apply(%Game{}, event), root_id: event.root_node_id]
    end

    test "rejects square names that do not exist", %{game: game, root_id: root_id} do
      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: "z9",
        to: "e4",
        player_id: @white
      }

      assert {:error, :illegal_move} = Game.execute(game, cmd)
    end

    test "rejects missing squares", %{game: game, root_id: root_id} do
      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        from: nil,
        to: nil,
        player_id: @white
      }

      assert {:error, :illegal_move} = Game.execute(game, cmd)
    end

    test "rejects a node_id that already exists", %{game: game, root_id: root_id} do
      cmd = %MakeMove{
        game_id: @game_id,
        from_node_id: root_id,
        node_id: root_id,
        from: "e2",
        to: "e4",
        player_id: @white
      }

      assert {:error, :node_id_taken} = Game.execute(game, cmd)
    end
  end

  describe "branch outcomes" do
    test "insufficient material is reported with its own reason" do
      cmd = %StartGame{
        game_id: @game_id,
        white_player_id: @white,
        black_player_id: @black,
        initial_fen: "4k3/8/8/8/8/8/4K3/4r3 w - - 0 1"
      }

      {:ok, [started]} = Game.execute(%Game{}, cmd)
      game = Game.apply(%Game{}, started)

      move = %MakeMove{
        game_id: @game_id,
        from_node_id: started.root_node_id,
        from: "e2",
        to: "e1",
        player_id: @white
      }

      assert {:ok, [%MoveMade{}, %GameEnded{reason: :insufficient_material, scope: :branch}]} =
               Game.execute(game, move)
    end
  end
end
