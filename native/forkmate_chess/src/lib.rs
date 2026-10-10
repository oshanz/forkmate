use rustler::Atom;
use shakmaty::{
    fen::Fen, san::SanPlus, uci::UciMove, CastlingMode, Chess, EnPassantMode, Position,
};

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

fn outcome_label(pos: &Chess) -> &'static str {
    if pos.is_checkmate() {
        "checkmate"
    } else if pos.is_stalemate() {
        "stalemate"
    } else if pos.is_insufficient_material() {
        "insufficient_material"
    } else if pos.halfmoves() >= 100 {
        "fifty_move"
    } else {
        "ongoing"
    }
}

fn check_square(pos: &Chess) -> Option<String> {
    if pos.is_check() {
        pos.board().king_of(pos.turn()).map(|sq| sq.to_string())
    } else {
        None
    }
}

#[rustler::nif]
fn apply_move(fen: &str, uci: &str) -> Result<(String, String, String, Option<String>), Atom> {
    let pos = parse_position(fen)?;
    let uci: UciMove = uci.parse().map_err(|_| atoms::invalid_uci())?;
    let mv = uci.to_move(&pos).map_err(|_| atoms::illegal_move())?;
    // shakmaty also accepts king-takes-own-rook castling notation (e1h1); we only
    // accept the standard king-to-destination form (e1g1).
    if UciMove::from_standard(mv) != uci {
        return Err(atoms::illegal_move());
    }

    let san = SanPlus::from_move(pos.clone(), mv).to_string();
    let next = pos.play(mv).map_err(|_| atoms::illegal_move())?;

    Ok((
        Fen::from_position(&next, EnPassantMode::Always).to_string(),
        san,
        outcome_label(&next).to_string(),
        check_square(&next),
    ))
}

#[rustler::nif]
fn outcome(fen: &str) -> Result<String, Atom> {
    let pos = parse_position(fen)?;
    Ok(outcome_label(&pos).to_string())
}

#[rustler::nif]
fn check_square_of(fen: &str) -> Result<Option<String>, Atom> {
    let pos = parse_position(fen)?;
    Ok(check_square(&pos))
}

rustler::init!("Elixir.Forkmate.Chess.Native");
