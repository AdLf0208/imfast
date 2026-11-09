//  Im-Fast's behaviour in Horizon: the server's movement checks start off.
//
//  Im-Fast (see `FINDINGS.md`) rewrites five constants of NeoForge's
//  `ServerGamePacketListenerImpl`, so a guest that moves faster than the
//  server expects is not sent back. Horizon reads two of those thresholds from
//  the game rules `player_movement_check` and `elytra_movement_check`
//  (`crates/horizon-client/src/game/lan.rs`: `Hub::movement_checks`), so this
//  port asks the console to put both rules off, once for each open world.
//
//  The other three constants (the two "moved wrongly" checks and the vehicle's
//  100) have no rule and no stamped hook at this pin; `notes.md` carries the
//  gap.

/// The rules `Hub::movement_checks` reads each pass: the player's
/// "moved too quickly" limit (Im-Fast's 100) and the elytra one (its 300).
pub const RULES: [&str; 2] = ["player_movement_check", "elytra_movement_check"];

/// The console line that puts `rule` at `value`.
pub fn set_rule(rule: &str, value: bool) -> String {
    format!("gamerule {rule} {value}")
}

/// The lines that turn both movement checks off, in [`RULES`] order.
pub fn off_lines() -> Vec<String> {
    RULES.iter().map(|rule| set_rule(rule, false)).collect()
}

/// What is left to do for the open world.
///
/// The rules are saved with the world, so they are set once per open, on the
/// first running server tick of it: an operator who turns a check back on
/// keeps it on for that session, which a mixin could not allow.
#[derive(Debug, Default)]
pub struct Applied {
    /// The epoch of the open whose rules are already off.
    epoch: Option<u64>,
}

impl Applied {
    /// Nothing applied yet.
    pub const fn new() -> Self {
        Self { epoch: None }
    }

    /// The lines to run at the end of this server tick, or `None` when this
    /// world's rules are already off (or its world is not running yet).
    pub fn on_tick(&mut self, epoch: u64, world_running: bool) -> Option<Vec<String>> {
        if !world_running || self.epoch == Some(epoch) {
            return None;
        }
        self.epoch = Some(epoch);
        Some(off_lines())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_rule_line_is_the_console_command_that_sets_it() {
        assert_eq!(set_rule("pvp", true), "gamerule pvp true");
        assert_eq!(set_rule("pvp", false), "gamerule pvp false");
    }

    #[test]
    fn the_checks_are_turned_off_by_their_two_rules() {
        assert_eq!(
            off_lines(),
            [
                "gamerule player_movement_check false",
                "gamerule elytra_movement_check false",
            ]
        );
    }

    #[test]
    fn the_first_running_tick_of_a_world_turns_them_off_once() {
        let mut applied = Applied::new();
        assert_eq!(applied.on_tick(7, true), Some(off_lines()));
        assert_eq!(applied.on_tick(7, true), None);
        assert_eq!(applied.on_tick(7, true), None);
    }

    #[test]
    fn a_world_that_is_not_running_waits_for_one_that_is() {
        let mut applied = Applied::new();
        assert_eq!(applied.on_tick(7, false), None);
        assert_eq!(applied.on_tick(7, false), None);
        assert_eq!(applied.on_tick(7, true), Some(off_lines()));
    }

    #[test]
    fn a_new_world_turns_them_off_again() {
        let mut applied = Applied::new();
        assert_eq!(applied.on_tick(7, true), Some(off_lines()));
        assert_eq!(applied.on_tick(8, true), Some(off_lines()));
        assert_eq!(applied.on_tick(8, true), None);
    }
}
