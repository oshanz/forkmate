defmodule Forkmate.Chess.Rules do
  @moduledoc """
  Pure Elixir chess rules engine.

  Provides legal move generation, move application, check/checkmate/stalemate
  detection, SAN formatting, and perft testing.
  """

  alias Forkmate.Chess.{Move, Piece, Position, Square}

  # --- Precalculated Tables ---

  @knight_offsets [{-2, -1}, {-2, 1}, {-1, -2}, {-1, 2}, {1, -2}, {1, 2}, {2, -1}, {2, 1}]
  @king_offsets [{-1, -1}, {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, -1}, {1, 0}, {1, 1}]
  @orthogonal_dirs [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]
  @diagonal_dirs [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]

  @knight_moves Map.new(0..63, fn sq ->
                  file = rem(sq, 8)
                  rank = div(sq, 8)

                  targets =
                    for {df, dr} <- @knight_offsets,
                        f = file + df,
                        r = rank + dr,
                        f in 0..7 and r in 0..7,
                        do: f + r * 8

                  {sq, targets}
                end)

  @king_moves Map.new(0..63, fn sq ->
                file = rem(sq, 8)
                rank = div(sq, 8)

                targets =
                  for {df, dr} <- @king_offsets,
                      f = file + df,
                      r = rank + dr,
                      f in 0..7 and r in 0..7,
                      do: f + r * 8

                {sq, targets}
              end)

  @orthogonal_rays Map.new(0..63, fn sq ->
                     file = rem(sq, 8)
                     rank = div(sq, 8)

                     rays =
                       Enum.map(@orthogonal_dirs, fn {df, dr} ->
                         Stream.iterate(1, &(&1 + 1))
                         |> Stream.map(fn step -> {file + df * step, rank + dr * step} end)
                         |> Stream.take_while(fn {f, r} -> f in 0..7 and r in 0..7 end)
                         |> Enum.map(fn {f, r} -> f + r * 8 end)
                       end)

                     {sq, rays}
                   end)

  @diagonal_rays Map.new(0..63, fn sq ->
                   file = rem(sq, 8)
                   rank = div(sq, 8)

                   rays =
                     Enum.map(@diagonal_dirs, fn {df, dr} ->
                       Stream.iterate(1, &(&1 + 1))
                       |> Stream.map(fn step -> {file + df * step, rank + dr * step} end)
                       |> Stream.take_while(fn {f, r} -> f in 0..7 and r in 0..7 end)
                       |> Enum.map(fn {f, r} -> f + r * 8 end)
                     end)

                   {sq, rays}
                 end)

  @pawn_attacks_white Map.new(0..63, fn sq ->
                        file = rem(sq, 8)
                        rank = div(sq, 8)

                        targets =
                          for df <- [-1, 1],
                              f = file + df,
                              r = rank + 1,
                              f in 0..7 and r in 0..7,
                              do: f + r * 8

                        {sq, targets}
                      end)

  @pawn_attacks_black Map.new(0..63, fn sq ->
                        file = rem(sq, 8)
                        rank = div(sq, 8)

                        targets =
                          for df <- [-1, 1],
                              f = file + df,
                              r = rank - 1,
                              f in 0..7 and r in 0..7,
                              do: f + r * 8

                        {sq, targets}
                      end)

  # --- Public API ---

  @spec legal_moves(Position.t()) :: [Move.t()]
  def legal_moves(%Position{} = pos) do
    pos
    |> pseudo_legal_moves()
    |> Enum.filter(&move_legal?(pos, &1))
  end

  @spec legal_move?(Position.t(), Move.t()) :: boolean()
  def legal_move?(%Position{} = pos, %Move{} = move) do
    move in legal_moves(pos)
  end

  @spec in_check?(Position.t(), Piece.color()) :: boolean()
  def in_check?(%Position{board: board}, color) do
    king_sq = find_king(board, color)
    king_sq != nil and square_attacked?(board, king_sq, Piece.opponent(color))
  end

  @spec check_square(Position.t()) :: Square.name() | nil
  def check_square(%Position{} = pos) do
    if in_check?(pos, pos.active_color) do
      case find_king(pos.board, pos.active_color) do
        nil -> nil
        sq -> Square.to_name(sq)
      end
    else
      nil
    end
  end

  @spec apply_move(Position.t(), Move.t()) ::
          {:ok, Position.t(), map()} | {:error, term()}
  def apply_move(%Position{} = pos, %Move{} = move) do
    moves = legal_moves(pos)

    matching_move =
      Enum.find(moves, fn m ->
        m.from == move.from and m.to == move.to and m.promotion == move.promotion
      end)

    if matching_move do
      san_str = san_for_move(pos, matching_move, moves)
      captured_piece = Map.get(pos.board, matching_move.to)
      next_pos = execute_move(pos, matching_move)
      is_check = in_check?(next_pos, next_pos.active_color)
      next_moves = legal_moves(next_pos)
      outcome_val = determine_move_outcome(pos, next_pos, next_moves, is_check)

      meta = %{
        san: san_str,
        from: Square.to_name(matching_move.from),
        to: Square.to_name(matching_move.to),
        promotion: matching_move.promotion,
        captured_piece: captured_piece,
        is_check: is_check,
        is_checkmate: is_check and next_moves == [],
        outcome: outcome_val
      }

      {:ok, next_pos, meta}
    else
      {:error, :illegal_move}
    end
  end

  defp determine_move_outcome(pos, _next_pos, [], true), do: {:checkmate, pos.active_color}
  defp determine_move_outcome(_pos, _next_pos, [], false), do: :stalemate

  defp determine_move_outcome(_pos, next_pos, _moves, _check) do
    cond do
      insufficient_material?(next_pos.board) -> :insufficient_material
      next_pos.halfmove_clock >= 100 -> :fifty_move
      true -> :ongoing
    end
  end

  @spec outcome(Position.t(), [Position.t()]) ::
          :ongoing
          | {:checkmate, Piece.color()}
          | :stalemate
          | :insufficient_material
          | :fifty_move
          | :threefold_repetition
  def outcome(%Position{} = pos, history \\ []) do
    moves = legal_moves(pos)
    check? = in_check?(pos, pos.active_color)

    cond do
      moves == [] and check? ->
        {:checkmate, Piece.opponent(pos.active_color)}

      moves == [] and not check? ->
        :stalemate

      insufficient_material?(pos.board) ->
        :insufficient_material

      pos.halfmove_clock >= 100 ->
        :fifty_move

      threefold_repetition?(pos, history) ->
        :threefold_repetition

      true ->
        :ongoing
    end
  end

  @spec san(Position.t(), Move.t()) :: String.t()
  def san(%Position{} = pos, %Move{} = move) do
    moves = legal_moves(pos)
    san_for_move(pos, move, moves)
  end

  @spec perft(Position.t(), non_neg_integer()) :: non_neg_integer()
  def perft(%Position{}, 0), do: 1

  def perft(%Position{} = pos, 1) do
    length(legal_moves(pos))
  end

  def perft(%Position{} = pos, depth) when depth > 1 do
    pos
    |> legal_moves()
    |> Enum.reduce(0, fn move, acc ->
      next_pos = execute_move(pos, move)
      acc + perft(next_pos, depth - 1)
    end)
  end

  # --- Move Generation Internals ---

  defp pseudo_legal_moves(%Position{board: board, active_color: color} = pos) do
    Enum.flat_map(board, fn
      {sq, {^color, :pawn}} -> pawn_moves(pos, sq, color)
      {sq, {^color, :knight}} -> knight_moves(board, sq, color)
      {sq, {^color, :bishop}} -> bishop_moves(board, sq, color)
      {sq, {^color, :rook}} -> rook_moves(board, sq, color)
      {sq, {^color, :queen}} -> queen_moves(board, sq, color)
      {sq, {^color, :king}} -> king_moves(pos, sq, color)
      _ -> []
    end)
  end

  defp pawn_moves(%Position{board: board, en_passant: ep}, sq, :white) do
    rank = div(sq, 8)
    one_step = sq + 8
    two_step = sq + 16

    single_pushes =
      if Map.has_key?(board, one_step) do
        []
      else
        pawn_advance_moves(sq, one_step, rank == 6)
      end

    double_pushes =
      if rank == 1 and not Map.has_key?(board, one_step) and not Map.has_key?(board, two_step) do
        [%Move{from: sq, to: two_step}]
      else
        []
      end

    captures =
      for target <- Map.fetch!(@pawn_attacks_white, sq),
          Map.get(board, target) in [
            {:black, :pawn},
            {:black, :knight},
            {:black, :bishop},
            {:black, :rook},
            {:black, :queen},
            {:black, :king}
          ] or target == ep,
          move <- pawn_advance_moves(sq, target, rank == 6) do
        move
      end

    single_pushes ++ double_pushes ++ captures
  end

  defp pawn_moves(%Position{board: board, en_passant: ep}, sq, :black) do
    rank = div(sq, 8)
    one_step = sq - 8
    two_step = sq - 16

    single_pushes =
      if Map.has_key?(board, one_step) do
        []
      else
        pawn_advance_moves(sq, one_step, rank == 1)
      end

    double_pushes =
      if rank == 6 and not Map.has_key?(board, one_step) and not Map.has_key?(board, two_step) do
        [%Move{from: sq, to: two_step}]
      else
        []
      end

    captures =
      for target <- Map.fetch!(@pawn_attacks_black, sq),
          Map.get(board, target) in [
            {:white, :pawn},
            {:white, :knight},
            {:white, :bishop},
            {:white, :rook},
            {:white, :queen},
            {:white, :king}
          ] or target == ep,
          move <- pawn_advance_moves(sq, target, rank == 1) do
        move
      end

    single_pushes ++ double_pushes ++ captures
  end

  defp pawn_advance_moves(from, to, true) do
    for promo <- [:queen, :rook, :bishop, :knight] do
      %Move{from: from, to: to, promotion: promo}
    end
  end

  defp pawn_advance_moves(from, to, false) do
    [%Move{from: from, to: to}]
  end

  defp knight_moves(board, sq, color) do
    for target <- Map.fetch!(@knight_moves, sq),
        target_empty_or_enemy?(board, target, color) do
      %Move{from: sq, to: target}
    end
  end

  defp bishop_moves(board, sq, color) do
    sliding_moves(board, sq, Map.fetch!(@diagonal_rays, sq), color)
  end

  defp rook_moves(board, sq, color) do
    sliding_moves(board, sq, Map.fetch!(@orthogonal_rays, sq), color)
  end

  defp queen_moves(board, sq, color) do
    diag = sliding_moves(board, sq, Map.fetch!(@diagonal_rays, sq), color)
    ortho = sliding_moves(board, sq, Map.fetch!(@orthogonal_rays, sq), color)
    diag ++ ortho
  end

  defp sliding_moves(board, sq, rays, color) do
    Enum.flat_map(rays, &ray_moves(board, sq, &1, color))
  end

  defp ray_moves(board, sq, ray, color) do
    Enum.reduce_while(ray, [], fn target, acc ->
      case Map.get(board, target) do
        nil ->
          {:cont, [%Move{from: sq, to: target} | acc]}

        {^color, _} ->
          {:halt, acc}

        _ ->
          {:halt, [%Move{from: sq, to: target} | acc]}
      end
    end)
  end

  defp king_moves(%Position{board: board, castling: castling} = pos, sq, color) do
    standard_moves =
      for target <- Map.fetch!(@king_moves, sq),
          target_empty_or_enemy?(board, target, color) do
        %Move{from: sq, to: target}
      end

    castling_moves = castling_moves(pos, sq, color, castling)
    standard_moves ++ castling_moves
  end

  defp castling_moves(%Position{board: board}, 4, :white, castling) do
    white_kingside_castling(board, castling) ++ white_queenside_castling(board, castling)
  end

  defp castling_moves(%Position{board: board}, 60, :black, castling) do
    black_kingside_castling(board, castling) ++ black_queenside_castling(board, castling)
  end

  defp castling_moves(_, _, _, _), do: []

  defp white_kingside_castling(board, castling) do
    can_castle =
      MapSet.member?(castling, :K) and
        Map.get(board, 5) == nil and Map.get(board, 6) == nil and
        Map.get(board, 7) == {:white, :rook} and
        not square_attacked?(board, 4, :black) and
        not square_attacked?(board, 5, :black) and
        not square_attacked?(board, 6, :black)

    if can_castle, do: [%Move{from: 4, to: 6}], else: []
  end

  defp white_queenside_castling(board, castling) do
    can_castle =
      MapSet.member?(castling, :Q) and
        Map.get(board, 3) == nil and Map.get(board, 2) == nil and Map.get(board, 1) == nil and
        Map.get(board, 0) == {:white, :rook} and
        not square_attacked?(board, 4, :black) and
        not square_attacked?(board, 3, :black) and
        not square_attacked?(board, 2, :black)

    if can_castle, do: [%Move{from: 4, to: 2}], else: []
  end

  defp black_kingside_castling(board, castling) do
    can_castle =
      MapSet.member?(castling, :k) and
        Map.get(board, 61) == nil and Map.get(board, 62) == nil and
        Map.get(board, 63) == {:black, :rook} and
        not square_attacked?(board, 60, :white) and
        not square_attacked?(board, 61, :white) and
        not square_attacked?(board, 62, :white)

    if can_castle, do: [%Move{from: 60, to: 62}], else: []
  end

  defp black_queenside_castling(board, castling) do
    can_castle =
      MapSet.member?(castling, :q) and
        Map.get(board, 59) == nil and Map.get(board, 58) == nil and Map.get(board, 57) == nil and
        Map.get(board, 56) == {:black, :rook} and
        not square_attacked?(board, 60, :white) and
        not square_attacked?(board, 59, :white) and
        not square_attacked?(board, 58, :white)

    if can_castle, do: [%Move{from: 60, to: 58}], else: []
  end

  defp target_empty_or_enemy?(board, target, color) do
    case Map.get(board, target) do
      nil -> true
      {^color, _} -> false
      _ -> true
    end
  end

  # --- Legality & Attack Checks ---

  defp move_legal?(%Position{board: board, active_color: color, en_passant: ep}, %Move{} = move) do
    temp_board = apply_move_to_board(board, move, ep)
    king_sq = find_king(temp_board, color)
    king_sq != nil and not square_attacked?(temp_board, king_sq, Piece.opponent(color))
  end

  defp apply_move_to_board(board, %Move{from: from, to: to, promotion: promo}, ep) do
    {color, type} = Map.fetch!(board, from)
    cleared_board = clear_moved_squares(board, from, to, type, color, ep)
    placed_piece = if promo, do: {color, promo}, else: {color, type}
    Map.put(cleared_board, to, placed_piece)
  end

  defp clear_moved_squares(board, from, to, :pawn, color, ep) when to == ep and from != to do
    captured_pawn_sq = if(color == :white, do: to - 8, else: to + 8)
    board |> Map.delete(from) |> Map.delete(captured_pawn_sq)
  end

  defp clear_moved_squares(board, from, to, :king, _color, _ep) when abs(from - to) == 2 do
    board
    |> Map.delete(from)
    |> move_castling_rook(from, to)
  end

  defp clear_moved_squares(board, from, _to, _type, _color, _ep) do
    Map.delete(board, from)
  end

  defp move_castling_rook(board, 4, 6), do: board |> Map.delete(7) |> Map.put(5, {:white, :rook})
  defp move_castling_rook(board, 4, 2), do: board |> Map.delete(0) |> Map.put(3, {:white, :rook})

  defp move_castling_rook(board, 60, 62),
    do: board |> Map.delete(63) |> Map.put(61, {:black, :rook})

  defp move_castling_rook(board, 60, 58),
    do: board |> Map.delete(56) |> Map.put(59, {:black, :rook})

  @spec square_attacked?(%{Square.index() => Piece.t()}, Square.index(), Piece.color()) ::
          boolean()
  def square_attacked?(board, sq, by_color) do
    pawn_attacked?(board, sq, by_color) or
      knight_attacked?(board, sq, by_color) or
      king_attacked?(board, sq, by_color) or
      sliding_attacked?(board, sq, Map.fetch!(@diagonal_rays, sq), by_color, [:bishop, :queen]) or
      sliding_attacked?(board, sq, Map.fetch!(@orthogonal_rays, sq), by_color, [:rook, :queen])
  end

  defp pawn_attacked?(board, sq, :white) do
    Enum.any?(Map.fetch!(@pawn_attacks_black, sq), fn source ->
      Map.get(board, source) == {:white, :pawn}
    end)
  end

  defp pawn_attacked?(board, sq, :black) do
    Enum.any?(Map.fetch!(@pawn_attacks_white, sq), fn source ->
      Map.get(board, source) == {:black, :pawn}
    end)
  end

  defp knight_attacked?(board, sq, by_color) do
    Enum.any?(Map.fetch!(@knight_moves, sq), fn source ->
      Map.get(board, source) == {by_color, :knight}
    end)
  end

  defp king_attacked?(board, sq, by_color) do
    Enum.any?(Map.fetch!(@king_moves, sq), fn source ->
      Map.get(board, source) == {by_color, :king}
    end)
  end

  defp sliding_attacked?(board, _sq, rays, by_color, types) do
    Enum.any?(rays, &ray_attacked?(&1, board, by_color, types))
  end

  defp ray_attacked?(ray, board, by_color, types) do
    Enum.reduce_while(ray, false, fn target, _acc ->
      check_ray_square(target, board, by_color, types)
    end)
  end

  defp check_ray_square(target, board, by_color, types) do
    case Map.get(board, target) do
      nil -> {:cont, false}
      {^by_color, type} -> {:halt, Enum.member?(types, type)}
      _ -> {:halt, false}
    end
  end

  defp find_king(board, color) do
    Enum.find_value(board, fn
      {sq, {^color, :king}} -> sq
      _ -> nil
    end)
  end

  # --- State Evolution ---

  defp execute_move(%Position{} = pos, %Move{} = move) do
    piece = Map.fetch!(pos.board, move.from)
    {color, type} = piece
    new_board = apply_move_to_board(pos.board, move, pos.en_passant)

    # Castling rights revocation
    new_castling = update_castling_rights(pos.castling, color, type, move.from, move.to)

    # En passant square calculation
    new_ep =
      if type == :pawn and abs(move.from - move.to) == 16 do
        div(move.from + move.to, 2)
      else
        nil
      end

    # Halfmove clock
    capture? = Map.has_key?(pos.board, move.to) or (type == :pawn and move.to == pos.en_passant)

    new_halfmove =
      if type == :pawn or capture? do
        0
      else
        pos.halfmove_clock + 1
      end

    # Fullmove number
    new_fullmove =
      if color == :black do
        pos.fullmove_number + 1
      else
        pos.fullmove_number
      end

    %Position{
      board: new_board,
      active_color: Piece.opponent(color),
      castling: new_castling,
      en_passant: new_ep,
      halfmove_clock: new_halfmove,
      fullmove_number: new_fullmove
    }
  end

  defp update_castling_rights(castling, :white, :king, _from, _to) do
    castling |> MapSet.delete(:K) |> MapSet.delete(:Q)
  end

  defp update_castling_rights(castling, :black, :king, _from, _to) do
    castling |> MapSet.delete(:k) |> MapSet.delete(:q)
  end

  defp update_castling_rights(castling, _color, _type, from, to) do
    castling
    |> check_corner(from)
    |> check_corner(to)
  end

  defp check_corner(castling, 0), do: MapSet.delete(castling, :Q)
  defp check_corner(castling, 7), do: MapSet.delete(castling, :K)
  defp check_corner(castling, 56), do: MapSet.delete(castling, :q)
  defp check_corner(castling, 63), do: MapSet.delete(castling, :k)
  defp check_corner(castling, _), do: castling

  # --- SAN Formatting ---

  defp san_for_move(pos, move, all_legal_moves) do
    {_color, type} = Map.fetch!(pos.board, move.from)
    next_pos = execute_move(pos, move)
    check_suffix = san_check_suffix(next_pos)

    body =
      case castling_san(type, move.from, move.to) do
        nil when type == :pawn -> san_pawn_move(pos, move)
        nil -> san_piece_move(pos, move, type, all_legal_moves)
        san -> san
      end

    body <> check_suffix
  end

  defp castling_san(:king, 4, 6), do: "O-O"
  defp castling_san(:king, 4, 2), do: "O-O-O"
  defp castling_san(:king, 60, 62), do: "O-O"
  defp castling_san(:king, 60, 58), do: "O-O-O"
  defp castling_san(_, _, _), do: nil

  defp san_check_suffix(next_pos) do
    if in_check?(next_pos, next_pos.active_color) do
      if legal_moves(next_pos) == [] do
        "#"
      else
        "+"
      end
    else
      ""
    end
  end

  defp san_pawn_move(pos, move) do
    capture? =
      Map.has_key?(pos.board, move.to) or
        (pos.en_passant != nil and move.to == pos.en_passant)

    promo_str =
      case move.promotion do
        :queen -> "=Q"
        :rook -> "=R"
        :bishop -> "=B"
        :knight -> "=N"
        nil -> ""
      end

    if capture? do
      from_file = Square.file_name(rem(move.from, 8))
      "#{from_file}x#{Square.to_name(move.to)}#{promo_str}"
    else
      "#{Square.to_name(move.to)}#{promo_str}"
    end
  end

  defp san_piece_move(pos, move, type, all_legal_moves) do
    piece_letter =
      case type do
        :knight -> "N"
        :bishop -> "B"
        :rook -> "R"
        :queen -> "Q"
        :king -> "K"
      end

    capture? = Map.has_key?(pos.board, move.to)
    capture_str = if capture?, do: "x", else: ""

    disambiguation = disambiguate(pos, move, type, all_legal_moves)
    "#{piece_letter}#{disambiguation}#{capture_str}#{Square.to_name(move.to)}"
  end

  defp disambiguate(pos, move, type, all_legal_moves) do
    candidates =
      Enum.filter(all_legal_moves, fn m ->
        m.from != move.from and m.to == move.to and
          Map.get(pos.board, m.from) == {pos.active_color, type}
      end)

    if candidates == [] do
      ""
    else
      same_file? = Enum.any?(candidates, fn m -> rem(m.from, 8) == rem(move.from, 8) end)
      same_rank? = Enum.any?(candidates, fn m -> div(m.from, 8) == div(move.from, 8) end)

      from_file = Square.file_name(rem(move.from, 8))
      from_rank = Integer.to_string(div(move.from, 8) + 1)

      cond do
        not same_file? -> from_file
        not same_rank? -> from_rank
        true -> from_file <> from_rank
      end
    end
  end

  # --- Draws: Insufficient Material & Repetition ---

  defp insufficient_material?(board) do
    pieces = Map.values(board)

    case pieces do
      [{:white, :king}, {:black, :king}] ->
        true

      [{:black, :king}, {:white, :king}] ->
        true

      # K+B vs K or K+N vs K
      [p1, p2, p3] ->
        minor_piece_draw?(p1, p2, p3)

      # K+B vs K+B same color squares
      [p1, p2, p3, p4] ->
        bishops_same_color_draw?(board, p1, p2, p3, p4)

      _ ->
        false
    end
  end

  defp minor_piece_draw?(p1, p2, p3) do
    list = [p1, p2, p3]
    white_pieces = Enum.filter(list, &match?({:white, _}, &1))
    black_pieces = Enum.filter(list, &match?({:black, _}, &1))

    case {white_pieces, black_pieces} do
      {[{:white, :king}, {:white, type}], [{:black, :king}]} when type in [:bishop, :knight] ->
        true

      {[{:white, :king}], [{:black, :king}, {:black, type}]} when type in [:bishop, :knight] ->
        true

      _ ->
        false
    end
  end

  defp bishops_same_color_draw?(board, p1, p2, p3, p4) do
    list = [p1, p2, p3, p4]

    has_kings_and_bishops =
      Enum.member?(list, {:white, :king}) and
        Enum.member?(list, {:black, :king}) and
        Enum.member?(list, {:white, :bishop}) and
        Enum.member?(list, {:black, :bishop})

    if has_kings_and_bishops do
      bishops =
        Enum.filter(board, fn {_sq, piece} ->
          piece in [{:white, :bishop}, {:black, :bishop}]
        end)

      case bishops do
        [{sq1, _}, {sq2, _}] ->
          rem(rem(sq1, 8) + div(sq1, 8), 2) == rem(rem(sq2, 8) + div(sq2, 8), 2)

        _ ->
          false
      end
    else
      false
    end
  end

  defp threefold_repetition?(current_pos, history) do
    # Position equivalence requires same board, active_color, castling, and en_passant.
    all_positions = [current_pos | history]
    current_key = position_key(current_pos)

    count =
      Enum.count(all_positions, fn pos ->
        position_key(pos) == current_key
      end)

    count >= 3
  end

  defp position_key(%Position{
         board: board,
         active_color: color,
         castling: castling,
         en_passant: ep
       }) do
    {board, color, castling, ep}
  end
end
