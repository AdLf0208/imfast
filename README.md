# Im-Fast (Horizon port)

A Horizon port of [I'm Fast](https://github.com/Gabriel-Hiss/Im-Fast) by Gabriel
Hiss: it removes Minecraft's built-in movement limits on servers.

**Status: first slice.** Horizon reads two of the five thresholds the original
mixin patches from game rules, so this port switches those two off once per open
world:

- `player_movement_check` — the "moved too quickly" pull-back for players
- `elytra_movement_check` — the same for elytra flight

A guest's long jump is kept while the rules are off, and refused when they are
back on. Not yet ported (needs upstream hooks): the two "moved wrongly"
thresholds and the vehicle speed limit.

## Install

Add the mod in the Horizon launcher (Mods → Build), or download
`imfast.hnmod` from the release and install it with a native-mod capable
launcher. Native mods are built into the game and run with the player's rights.

## Build from source

```sh
cargo test
python3 tools/horizon.py check --horizon <horizon checkout>
python3 tools/horizon.py build --horizon <horizon checkout>
python3 tools/package.py
```

Pinned to Horizon `1d63e0a` and horizon-mixins `5a64af93` for game 26.3.

## Credits and licence

Original mod and behaviour: Gabriel Hiss. Port: AdLf0208. MIT — see
[LICENSE](LICENSE); original copyright and licence notices are preserved.
