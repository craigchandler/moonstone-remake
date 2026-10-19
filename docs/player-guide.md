# Playing a local build

Extract the entire locally created ZIP. Linux: run `Moonstone.sh` (enable
execution in file properties if needed). Windows: run `Moonstone.cmd`. Godot and
native resources are included; no disk images or development tools are needed.
The public source repository does not provide these asset-containing packages.

Choose **New journey** for a solo knight, or **New journey → Local players** to
configure four human/computer slots, names and controller ports. Humans have
separate progress and share the world. Map turns can share a keyboard; human
duel defenders use the number pad or their assigned controller.

A new solo knight starts at its own home village. Press Enter, Z, the controller
confirm button or click to enter while the village flashes. The character sheet
opens; entering restores one life when below three. Leave the sheet to spend
the turn and rest. Health recovery happens when the round completes, after the
other knights act. Continue preserves the saved location of an existing game.

## Practice

Choose **Practice** on the title menu. Up/Down chooses an opponent; Left/Right
changes your knight colour. Enter, Space, Z or **Begin** starts the fight. With
a mouse, click an opponent to preview it, then click **Begin**. Controllers use
the stick/D-pad and confirm button.

Practice includes the native creature encounters, a knight duel and the Black
Knight. It uses a fresh standard kit and the existing encounter waves, AI and
combat rules. Each retry repeats the same starting state and combat seed.
It does not spend campaign lives or change equipment, treasure, experience,
world turns or saved progress. This expanded roster is a remake enhancement.

During practice, **R** retries immediately, **F1** opens controls and **Escape**
returns to the opponent picker. After a completed victory or defeat, Enter or
the controller confirm button retries; the controller retreat button returns
to opponents. Escape, **Back** or an arch column leaves the picker for the title.
Choose **Network duel** in Practice, or press N (controller next-page button).
On one computer choose **Host duel**. The other player enters the host's displayed
address and the same port, then chooses **Join duel**. The default port is27866.
Use matching builds on the same local network. Both choose **Ready** to begin.
Each controls its own knight with the usual combat controls. If both chose the
same colour, the guest receives the next colour.

After a round, confirm requests a rematch; both players must agree. Escape or
the controller retreat button leaves. Disconnect confirmation returns to Practice.
Local controls/pause menus do not pause the opponent: your knight receives
neutral input while they are open. Duels use no campaign lives or rewards.
This initial mode uses direct connections. Campaign networking, matchmaking,
relays, live rejoining and host migration remain future work.

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

Campaign networking, internet matchmaking, human cooperative encounters and enhanced rendering are
future work. Report reproducible issues with the build identity, platform and
input method. Original-game fidelity and platform runtime checks are separate
from automated tests.
