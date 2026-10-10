defmodule Forkmate.Bots.Seat do
  @moduledoc """
  Helpers for bot seats. A bot is an ordinary player id of the form
  `bot:stockfish:<level>`, so the `Game` aggregate needs no special casing.
  """

  @prefix "bot:stockfish:"

  @type level :: :easy | :medium | :hard | :max

  @spec levels() :: [level()]
  def levels, do: [:easy, :medium, :hard, :max]

  @spec new(level()) :: String.t()
  def new(level) when level in [:easy, :medium, :hard, :max], do: @prefix <> Atom.to_string(level)

  @spec parse_level(String.t() | nil) :: {:ok, level()} | {:error, :invalid_level}
  def parse_level(value) do
    case to_level(value) do
      {:ok, level} -> {:ok, level}
      :error -> {:error, :invalid_level}
    end
  end

  @spec bot?(String.t() | nil) :: boolean()
  def bot?(@prefix <> _), do: true
  def bot?(_), do: false

  @spec level(String.t()) :: {:ok, level()} | :error
  def level(@prefix <> name), do: to_level(name)
  def level(_), do: :error

  @spec label(String.t()) :: String.t()
  def label(@prefix <> name = id) do
    case to_level(name) do
      {:ok, level} -> "Stockfish (#{level |> Atom.to_string() |> String.capitalize()})"
      :error -> id
    end
  end

  def label(id), do: id

  @spec human_color(String.t(), String.t()) :: :white | :black | nil
  def human_color(white_id, black_id) do
    case {bot?(white_id), bot?(black_id)} do
      {true, false} -> :black
      {false, true} -> :white
      _ -> nil
    end
  end

  defp to_level("easy"), do: {:ok, :easy}
  defp to_level("medium"), do: {:ok, :medium}
  defp to_level("hard"), do: {:ok, :hard}
  defp to_level("max"), do: {:ok, :max}
  defp to_level(_), do: :error
end
