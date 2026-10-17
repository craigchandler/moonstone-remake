# Playing a local build

Extract the entire locally created ZIP. Linux: run `Moonstone.sh` (enable
execution in file properties if needed). Windows: run `Moonstone.cmd`. Godot and
native resources are included; no disk images or development tools are needed.
The public source repository does not provide these asset-containing packages.

Choose **New journey** for a solo knight, or **New journey → Local players** to
configure four human/computer slots, names and controller ports. Humans have
separate progress and share the world. Map turns can share a keyboard; human
duel defenders use the number pad or their assigned controller.

## Controls

| Action | Keyboard/mouse |
| --- | --- |
| Travel/move | Arrow keys |
| Enter an overlapping, flashing map location | Enter, Z or click |
| Inventory / end turn / menu / help | I / E / R / F1 |
| Swing / overhead / lunge / reverse | Z / X / C / V |
| Upward thrust / dagger / guard | A / D / Space |
| Escape a supported hold | Guard + Down |
| Retreat | Escape |
| Toggle gore / sound | G / F8 |
| Sound volume | F9 / F10 |

Loot and character screens use a sword cursor; click an arch column to exit.
Controller Start pauses; **Options → Controller** changes mappings. An absent
controller has a keyboard fallback. In human duels, the defender’s number-pad
8/4/2/6 moves, while 7/9/1/3/0/decimal/5 mirror the seven attacks/guard. Enter
begins the duel after its readiness screen.

## Progress

Normal play autosaves. Continue resumes the campaign. An unfinished fight
resumes at its entrance; settled loot retains remaining contents and earned
progress. Existing solo/party migrations are retained, but older executables
may reject newer saved values; keep a backup when changing versions.

Development shortcuts are available only when the launcher is given `--debug`.
Debug sessions keep progress/settings in memory and do not overwrite normal
saves. For a direct executable, pass the game flag after `--`.

Internet multiplayer, human cooperative encounters and enhanced rendering are
future work. Report reproducible issues with the build identity, platform and
input method. Original-game fidelity and platform runtime checks are separate
from automated tests.
