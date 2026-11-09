#!/usr/bin/env bash
# In-game check for Im-Fast (slice 1): the server's movement checks start off.
#
# Im-Fast raises five thresholds of NeoForge's movement validation so a guest is
# never sent back. Horizon reads two of them from the game rules
# `player_movement_check` and `elytra_movement_check`; this port puts both off
# on the first running server tick of an open world. The checks only run for a
# guest (`shouldCheckPlayerMovement` exempts the single-player owner), so the run
# is a LAN host and a LAN guest, and the "too quickly" limit is 100 blocks.
#
# Leg A (the modded game, a real guest):
#   1. the rules read false on the host at world start, before anything moves
#      the guest;
#   2. the guest jumps 200 blocks in one move (a client position write): the
#      guest stays there — no "moved too quickly" pull-back;
#   3. the host turns both rules back on with the vanilla command and the guest
#      jumps 200 blocks again: the server sends it back, so the same jump is
#      refused;
#   4. the two legs differ only in the rule, so the rule is the switch.
# Leg B (the unmodified game, control): both rules read true at world start, so
#   the flip in leg A is the mod's and not the engine's default.
#
# SELFTEST=1 reruns leg A's step-2 assertion inverted (the guest must have been
# sent back), which must fail: that proves the assertion is not vacuous.
set -euo pipefail
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/imfast
SHARED=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$PORT/target/horizon-cargo/fast/horizon-client}
CONTROL_GAME=${CONTROL_GAME:-$SHARED/horizon-client}
RES=${RES:-${HORIZON_RES:-$HOME/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/imfast-e2e.sock}
GSOCK=${GSOCK:-/tmp/opencode/imfast-e2e-guest.sock}
SELFTEST=${SELFTEST:-0}
JUMP=200

for f in "$CTL" "$GAME" "$CONTROL_GAME"; do
    [ -x "$f" ] || { echo "missing binary: $f" >&2; exit 1; }
done
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }

SCRATCH=$(mktemp -d "${E2E_TMP:-/tmp/opencode}"/imfast-home.XXXXXX)
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")" "$(dirname "$GSOCK")"
rm -f "$SOCK" "$GSOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
gctl() { "$CTL" --socket "$GSOCK" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
say() { echo "== $* =="; }

# The value a game rule has, read through the vanilla command on the console.
# `messages` replies newest first, so the first matching line is the answer to
# this query rather than an earlier one.
rule() { # game-caller rule-id
    local game=$1 id=$2
    "$game" command "gamerule $id" >/dev/null
    "$game" wait 2 >/dev/null
    "$game" messages 10 | jq -r '.chat[]' 2>/dev/null \
        | sed -n "s/^Game rule $id is currently set to \(.*\)$/\1/p" | head -1
}
pos_x() { "$1" state | jq -r '.player.position[0]'; }
near() { # value target tolerance
    awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < t) }'
}

# Every run ends with its status line, so the artefact proves the verdict.
finish() {
    local status=$?
    gctl quit >/dev/null 2>&1 || true
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
    echo "E2E EXIT:$status"
}
trap finish EXIT

launch() { # socket home binary
    local socket=$1 home=$2 binary=$3
    HORIZON_HOME=$home "$CTL" --socket "$socket" launch \
        --game "$binary" --headless --resources "$RES" --no-pause
}

say "leg A: a LAN host with the mod, and a guest"
launch "$SOCK" "$SCRATCH/host" "$GAME"
ctl open ImFastHost 20261109 creative >/dev/null
ctl wait-ready 400
ctl command "gamerule spawn_mobs false" >/dev/null
ctl command "defaultgamemode creative" >/dev/null
PX=$(ctl state | jq -r '.player.position[0]' | cut -d. -f1)
PY=$(ctl state | jq -r '.player.position[1]' | cut -d. -f1)
PZ=$(ctl state | jq -r '.player.position[2]' | cut -d. -f1)
ctl command "fill $((PX-8)) $((PY-1)) $((PZ-8)) $((PX+8)) $((PY-1)) $((PZ+8)) minecraft:stone" >/dev/null
ctl command "fill $((PX-8)) $PY $((PZ-8)) $((PX+8)) $((PY+6)) $((PZ+8)) minecraft:air" >/dev/null
ctl wait 10
PORT_NUMBER=$(ctl lan open 0 commands | jq -r '.port')
echo "LAN port: $PORT_NUMBER"
[ "$PORT_NUMBER" != "null" ] || fail "the host did not open its world to LAN"

launch "$GSOCK" "$SCRATCH/guest" "$GAME"
gctl connect "127.0.0.1:$PORT_NUMBER" Guest >/dev/null
gctl wait-for loaded --timeout 300 >/dev/null
gctl wait 40 >/dev/null

ROWS=$(ctl lan status | jq -r '.guests | length')
echo "guests on the host: $ROWS"
[ "$ROWS" -ge 1 ] || fail "the guest never joined the host's world"
GUEST_CREATIVE=$(gctl status | jq -r '.creative')
echo "guest creative: $GUEST_CREATIVE"
[ "$GUEST_CREATIVE" = true ] || fail "the guest is not creative, so \"moved wrongly\" would answer too"

say "the mod puts both movement checks off, at world start"
PLAYER_RULE=$(rule ctl player_movement_check)
ELYTRA_RULE=$(rule ctl elytra_movement_check)
echo "player_movement_check=$PLAYER_RULE elytra_movement_check=$ELYTRA_RULE"
[ "$PLAYER_RULE" = false ] || fail "player_movement_check is '$PLAYER_RULE', expected false"
[ "$ELYTRA_RULE" = false ] || fail "elytra_movement_check is '$ELYTRA_RULE', expected false"

say "a guest that jumps $JUMP blocks with the checks off is not sent back"
START=$(pos_x gctl)
echo "guest x before: $START"
gctl tp "$(awk -v x="$START" -v d="$JUMP" 'BEGIN{print x+d}')" "$PY" "$PZ" >/dev/null
gctl wait 40 >/dev/null
AFTER=$(pos_x gctl)
echo "guest x after: $AFTER (target $(awk -v x="$START" -v d="$JUMP" 'BEGIN{print x+d}'))"
near "$AFTER" "$(awk -v x="$START" -v d="$JUMP" 'BEGIN{print x+d}')" 5 \
    || fail "the guest was sent back: x=$AFTER, expected $((START + JUMP))"

if [ "$SELFTEST" = 1 ]; then
    say "selftest: expect the guest to have been sent back (must fail)"
    near "$AFTER" "$START" 5 \
        || fail "SELFTEST: the guest was not sent back, so the assertion is alive"
    echo "SELFTEST unexpectedly saw the guest sent back"
    exit 0
fi

say "the same jump with the checks on is refused, so the rule is the switch"
ctl command "gamerule player_movement_check true" >/dev/null
ctl command "gamerule elytra_movement_check true" >/dev/null
ctl wait 4 >/dev/null
PLAYER_RULE=$(rule ctl player_movement_check)
ELYTRA_RULE=$(rule ctl elytra_movement_check)
echo "player_movement_check=$PLAYER_RULE elytra_movement_check=$ELYTRA_RULE (set back by the host)"
[ "$PLAYER_RULE" = true ] || fail "the host could not set player_movement_check back on"
[ "$ELYTRA_RULE" = true ] || fail "the host could not set elytra_movement_check back on"
BEFORE=$(pos_x gctl)
echo "guest x before: $BEFORE"
gctl tp "$(awk -v x="$BEFORE" -v d="$JUMP" 'BEGIN{print x+d}')" "$PY" "$PZ" >/dev/null
gctl wait 40 >/dev/null
REFUSED=$(pos_x gctl)
echo "guest x after: $REFUSED (the server sent it back)"
near "$REFUSED" "$BEFORE" 5 \
    || fail "the guest kept the $JUMP-block jump with the checks on: x=$REFUSED, was $BEFORE"

say "leg B: the unmodified game starts with both checks on"
gctl quit >/dev/null 2>&1 || true
ctl quit >/dev/null 2>&1 || true
sleep 2
launch "$SOCK" "$SCRATCH/control" "$CONTROL_GAME"
ctl open ImFastControl 20261109 creative >/dev/null
ctl wait-ready 400 >/dev/null
PLAYER_RULE=$(rule ctl player_movement_check)
ELYTRA_RULE=$(rule ctl elytra_movement_check)
echo "player_movement_check=$PLAYER_RULE elytra_movement_check=$ELYTRA_RULE (no mod)"
[ "$PLAYER_RULE" = true ] || fail "the game without the mod reads player_movement_check='$PLAYER_RULE'"
[ "$ELYTRA_RULE" = true ] || fail "the game without the mod reads elytra_movement_check='$ELYTRA_RULE'"

echo "PASS: the mod puts player_movement_check and elytra_movement_check off at world start and a guest's $JUMP-block jump is kept; with the rules set back on the same jump is refused, and the unmodified game starts with both on"
