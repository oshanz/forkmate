defmodule Forkmate.Bots.SeatTest do
  use ExUnit.Case, async: true

  alias Forkmate.Bots.Seat

  test "new/1 builds a bot seat id" do
    assert Seat.new(:medium) == "bot:stockfish:medium"
  end

  test "parse_level/1 accepts known levels and rejects the rest" do
    assert Seat.parse_level("easy") == {:ok, :easy}
    assert Seat.parse_level("max") == {:ok, :max}
    assert Seat.parse_level("impossible") == {:error, :invalid_level}
    assert Seat.parse_level(nil) == {:error, :invalid_level}
  end

  test "bot?/1 and level/1" do
    assert Seat.bot?("bot:stockfish:hard")
    refute Seat.bot?("Player 1")
    refute Seat.bot?(nil)
    assert Seat.level("bot:stockfish:hard") == {:ok, :hard}
    assert Seat.level("bot:stockfish:nope") == :error
    assert Seat.level("Player 1") == :error
  end

  test "label/1" do
    assert Seat.label("bot:stockfish:medium") == "Stockfish (Medium)"
    assert Seat.label("Player 1") == "Player 1"
  end

  test "human_color/2 is the colour of the lone human, nil otherwise" do
    bot = Seat.new(:easy)
    assert Seat.human_color("Player 1", bot) == :white
    assert Seat.human_color(bot, "Player 1") == :black
    assert Seat.human_color("Player 1", "Player 2") == nil
    assert Seat.human_color(bot, Seat.new(:hard)) == nil
  end
end
