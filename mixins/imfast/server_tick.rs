// Runs at the head of `Game::native_server_tick` (API 4): turn the server's
// movement checks off once for the open world.
fn on_server_tick(
    game: &mut crate::game::Game<'_>,
    context: &NativeLifecycleContext,
    phase: ServerTickPhase,
) {
    crate::game::imfast_state::on_server_tick(game, context, phase);
}
