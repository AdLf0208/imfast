// Game-side glue for Im-Fast: the state the server-tick hook shares, and the
// console lines it runs. Injected into `crate::game` as `imfast_state`; it
// needs the game, so it is not part of the standalone library (only
// `runtime.rs` is).
//
// It runs at the end of an authoritative server tick (`native_server_tick`),
// which is where `native_run_command` is allowed (API 21): no player's state
// is swapped in there, unlike inside a player's hook. `world_lifecycle` would
// fire before the level's rules are the ones the hub reads, so the rule is set
// on the first running tick of the open instead.

use std::sync::{Mutex, PoisonError};

use crate::game::Game;
use crate::game::imfast::Applied;
use crate::game::native_lifecycle::{NativeLifecycleContext, ServerTickPhase};

/// The open world whose rules this session already put off.
static APPLIED: Mutex<Applied> = Mutex::new(Applied::new());

/// The end of an authoritative server tick: turn the two movement checks off
/// once for this open (see [`Applied`]), and then leave them alone, so an
/// operator who sets a rule back keeps it.
///
/// A line the console answers `not set` for changes nothing: `gamerule` fails
/// when the rule already holds the wanted value, which is the end state this
/// wants, so nothing is retried.
pub(super) fn on_server_tick(
    game: &mut Game<'_>,
    context: &NativeLifecycleContext,
    phase: ServerTickPhase,
) {
    let ServerTickPhase::ServerTickEnd { world_running } = phase else {
        return;
    };
    let lines = {
        let mut applied = APPLIED.lock().unwrap_or_else(PoisonError::into_inner);
        applied.on_tick(context.epoch.get(), world_running)
    };
    let Some(lines) = lines else {
        return;
    };
    for line in lines {
        let _ = game.native_run_command(&line);
    }
}
