defmodule Forkmate.Chess.Position do
  @moduledoc """
  Represents a chess position, including board layout, turn, castling rights,
  en passant square, and move clocks. Supports full FEN serialization.
  """

  alias Forkmate.Chess.{Piece, Square}

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  @type castling_right :: :K | :Q | :k | :q
  @type t :: %__MODULE__{
          board: %{Square.index() => Piece.t()},
          active_color: Piece.color(),
          castling: MapSet.t(castling_right()),
          en_passant: Square.index() | nil,
          halfmove_clock: non_neg_integer(),
          fullmove_number: pos_integer()
        }

  defstruct board: %{},
            active_color: :white,
            castling: MapSet.new([:K, :Q, :k, :q]),
            en_passant: nil,
            halfmove_clock: 0,
            fullmove_number: 1

  @spec start() :: t()
  def start do
    from_fen!(@start_fen)
  end

  @spec start_fen() :: String.t()
  def start_fen, do: @start_fen

  @spec from_fen(String.t()) :: {:ok, t()} | {:error, term()}
  def from_fen(fen) when is_binary(fen) do
    parts = String.split(String.trim(fen), ~r/\s+/)

    case parts do
      [placement, color_str, castling_str, ep_str | rest] ->
        with {:ok, board} <- parse_placement(placement),
             {:ok, color} <- parse_color(color_str),
             {:ok, castling} <- parse_castling(castling_str),
             {:ok, ep} <- parse_en_passant(ep_str) do
          {halfmove, fullmove} = parse_clocks(rest)

          {:ok,
           %__MODULE__{
             board: board,
             active_color: color,
             castling: castling,
             en_passant: ep,
             halfmove_clock: halfmove,
             fullmove_number: fullmove
           }}
        end

      _ ->
        {:error, :invalid_fen}
    end
  end

  @spec from_fen!(String.t()) :: t()
  def from_fen!(fen) do
    case from_fen(fen) do
      {:ok, pos} -> pos
      {:error, reason} -> raise ArgumentError, "Invalid FEN: #{inspect(fen)} (#{inspect(reason)})"
    end
  end

  @spec to_fen(t()) :: String.t()
  def to_fen(%__MODULE__{} = pos) do
    placement = format_placement(pos.board)
    color = if(pos.active_color == :white, do: "w", else: "b")
    castling = format_castling(pos.castling)
    ep = if(pos.en_passant, do: Square.to_name(pos.en_passant), else: "-")

    "#{placement} #{color} #{castling} #{ep} #{pos.halfmove_clock} #{pos.fullmove_number}"
  end

  defp format_placement(board) do
    Enum.map_join(7..0//-1, "/", fn rank -> format_rank(board, rank) end)
  end

  defp format_rank(board, rank) do
    {row_str, empty_count} = Enum.reduce(0..7, {"", 0}, &format_cell(board, rank, &1, &2))
    if empty_count > 0, do: "#{row_str}#{empty_count}", else: row_str
  end

  defp format_cell(board, rank, file, {acc, empty}) do
    sq = Square.from_coords(file, rank)

    case Map.get(board, sq) do
      nil ->
        {acc, empty + 1}

      piece ->
        prefix = if(empty > 0, do: "#{acc}#{empty}", else: acc)
        {"#{prefix}#{Piece.to_char(piece)}", 0}
    end
  end

  defp format_castling(castling) do
    rights =
      [:K, :Q, :k, :q]
      |> Enum.filter(&MapSet.member?(castling, &1))
      |> Enum.map_join("", &Atom.to_string/1)

    if rights == "", do: "-", else: rights
  end

  defp parse_placement(placement) do
    ranks = String.split(placement, "/")

    if length(ranks) == 8 do
      reduce_ranks(ranks)
    else
      {:error, :invalid_ranks_count}
    end
  end

  defp reduce_ranks(ranks) do
    ranks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}}, fn {rank_str, idx}, {:ok, acc} ->
      rank = 7 - idx

      case parse_rank_chars(rank_str, rank) do
        {:ok, rank_board} -> {:cont, {:ok, Map.merge(acc, rank_board)}}
        {:error, err} -> {:halt, {:error, err}}
      end
    end)
  end

  defp parse_rank_chars(rank_str, rank) do
    rank_str
    |> String.graphemes()
    |> Enum.reduce_while({:ok, %{}, 0}, &parse_char_in_rank(&1, rank, &2))
    |> validate_rank_result()
  end

  defp parse_char_in_rank(char, rank, {:ok, board, file}) do
    case Integer.parse(char) do
      {count, ""} when count in 1..8 and file + count <= 8 ->
        {:cont, {:ok, board, file + count}}

      :error when file < 8 ->
        parse_piece_char(char, rank, file, board)

      _ ->
        {:halt, {:error, :invalid_rank_length}}
    end
  end

  defp parse_piece_char(char, rank, file, board) do
    case Piece.from_char(char) do
      nil ->
        {:halt, {:error, {:invalid_piece_char, char}}}

      piece ->
        sq = Square.from_coords(file, rank)
        {:cont, {:ok, Map.put(board, sq, piece), file + 1}}
    end
  end

  defp validate_rank_result({:ok, board, 8}), do: {:ok, board}
  defp validate_rank_result({:ok, _, _}), do: {:error, :rank_length_not_8}
  defp validate_rank_result({:error, err}), do: {:error, err}

  defp parse_color("w"), do: {:ok, :white}
  defp parse_color("b"), do: {:ok, :black}
  defp parse_color(_), do: {:error, :invalid_active_color}

  defp parse_castling("-"), do: {:ok, MapSet.new()}

  defp parse_castling(str) do
    chars = String.graphemes(str)
    all_valid = Enum.all?(chars, &(&1 in ~w(K Q k q)))

    if all_valid do
      rights =
        chars
        |> Enum.map(&String.to_existing_atom/1)
        |> MapSet.new()

      {:ok, rights}
    else
      {:error, :invalid_castling}
    end
  end

  defp parse_en_passant("-"), do: {:ok, nil}

  defp parse_en_passant(str) do
    case Square.from_name(str) do
      nil -> {:error, :invalid_en_passant}
      sq -> {:ok, sq}
    end
  end

  defp parse_clocks([half_str, full_str | _]) do
    {half, _} = Integer.parse(half_str)
    {full, _} = Integer.parse(full_str)
    {half, full}
  rescue
    _ -> {0, 1}
  end

  defp parse_clocks([half_str]) do
    case Integer.parse(half_str) do
      {half, ""} -> {half, 1}
      _ -> {0, 1}
    end
  end

  defp parse_clocks([]), do: {0, 1}
end
