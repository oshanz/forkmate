use rustler::Atom;
use shakmaty::{fen::Fen, uci::UciMove, CastlingMode, Chess, Position};

mod atoms {
    rustler::atoms! {
        invalid_fen,
        illegal_move,
        invalid_uci,
    }
}

fn parse_position(fen: &str) -> Result<Chess, Atom> {
    let fen: Fen = fen.parse().map_err(|_| atoms::invalid_fen())?;
    fen.into_position(CastlingMode::Standard)
        .map_err(|_| atoms::invalid_fen())
}

#[rustler::nif]
fn legal_moves(fen: &str) -> Result<Vec<String>, Atom> {
    let pos = parse_position(fen)?;
    Ok(pos
        .legal_moves()
        .iter()
        .map(|m| UciMove::from_standard(*m).to_string())
        .collect())
}

rustler::init!("Elixir.Forkmate.Chess.Native");
