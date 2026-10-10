defmodule Forkmate.Chess.Native do
  @moduledoc """
  Rustler NIF wrapping the `shakmaty` chess crate (GPL-3.0-or-later).

  All functions take and return plain strings: FEN in, UCI moves out. Errors are
  `{:error, :invalid_fen | :illegal_move | :invalid_uci}`.
  """

  use Rustler, otp_app: :forkmate, crate: "forkmate_chess", path: "native/forkmate_chess"

  @spec legal_moves(String.t()) :: {:ok, [String.t()]} | {:error, :invalid_fen}
  def legal_moves(_fen), do: :erlang.nif_error(:nif_not_loaded)
end
