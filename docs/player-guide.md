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
address and the same port, then chooses **Join duel**. The default port is 27866.
Use matching builds on the same local network. Both choose **Ready** to begin.
Each controls its own knight with the usual combat controls. If both chose the
same colour, the guest receives the next colour.

After a round, confirm requests a rematch; both players must agree. Escape or
the controller retreat button leaves. Disconnect confirmation returns to Practice.
Local controls/pause menus do not pause the opponent: your knight receives
neutral input while they are open. Duels use no campaign lives or rewards.
A [standalone command-line host](server-guide.md) can also run the duel. Both
players choose **Join duel** using its address and port; neither game client
needs to choose Host. Use current matching client/server builds.

Practice duels use direct connections. Their match ends on disconnection.
Campaign reconnect behavior is described below.

## Network journey

For **in-game hosting**:

1. Choose **Network journey** on the title screen, select a knight with Left/Right
   and set **Humans** to the number of humans joining, including yourself (1–4).
2. Choose **Host new journey**. Give the other players the displayed host address
   and port. Remaining knight seats become computer controlled.
3. Each other player opens **Network journey**, enters that address/port, chooses
   a knight and selects **Join journey**. If a colour is already taken, the host
   assigns an available one; the lobby marks the assigned knight as **YOU**.
4. Every human chooses **Ready**. Play starts when the configured group is ready.

For **standalone hosting**, start the [command-line server](server-guide.md#host-a-campaign).
Every human uses **Join journey**; the server occupies no knight seat. The number
of humans comes from the server, and the lobby displays it.

Use matching client/server builds. The campaign default is **UDP 27867**;
practice duels use **UDP 27866**. On another computer, use the host's LAN address;
`127.0.0.1` refers to the same computer only. Allow the selected UDP port through
the host's firewall. Direct hosting provides no matchmaking or relay service.

Play follows classic turns. Enter starts your turn; arrows travel, Enter/Z enters
a highlighted location and E ends the turn. Use the usual combat/town controls.
When two human knights fight, both choose Ready and each uses the usual combat
controls on their own computer. Waiting players watch the active screen.
**I** opens your own inventory without pausing play; it is read-only outside
your turn and during battles. Opening inventory or a local pause menu sends
neutral input while the host continues for everyone else.

If a human leaves or loses connection, the campaign pauses and reserves their
knight. Rejoin the intended host from the same local game profile. Each human
chooses Ready after everyone returns. Automatic reconnect clears old held input.
Choosing the same colour alone cannot replace a missing reconnect key.

**Resume hosted game** resumes the last in-game host save remembered for that
port; use the same port and game profile. A standalone host resumes its specified
`--save` file. Host progress and reconnect keys use separate network files and
do not overwrite solo/local Continue. A live reconnect retains exact battle
state while the host survives. Restarting the host during an unfinished fight
returns to that fight's entrance, following existing safe disk-save behavior.

Use a separate game profile for each person. Multiple game instances using the
same local user-data folder share their stored reconnect keys. The automated
same-computer tests use isolated folders for this reason.

One host runs one campaign. Simultaneous turns, host migration, remote seat
recovery without the local key and multiple rooms within one process remain
future work. See [network troubleshooting](server-guide.md#addresses-backups-and-troubleshooting).

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
controller has a keyboard fallback. In local human duels sharing a keyboard,
the defender’s number-pad 8/4/2/6 moves, while 7/9/1/3/0/decimal/5 mirror the seven attacks/guard. Network players
each use the usual controls on their own computer. Enter begins a human duel
after its readiness screen.

## Progress

Normal play autosaves. Continue resumes the campaign. An unfinished fight
resumes at its entrance; settled loot retains remaining contents and earned
progress. Existing solo/party migrations are retained, but older executables
may reject newer saved values; keep a backup when changing versions.

## Save locations and backups

The game stores player data outside the extracted ZIP. Default user-data
locations are:

| Application | Linux | Windows |
| --- | --- | --- |
| Game client | `~/.local/share/godot/app_userdata/Moonstone Remake/` | `%APPDATA%\Godot\app_userdata\Moonstone Remake\` |
| Standalone server | `~/.local/share/godot/app_userdata/Moonstone Duel Server/` | `%APPDATA%\Godot\app_userdata\Moonstone Duel Server\` |

Linux `XDG_DATA_HOME` overrides the data-folder prefix. These are Godot's
[standard user-data locations](https://docs.godotengine.org/en/4.6/tutorials/io/data_paths.html#accessing-persistent-user-data-user).

- Solo/local Continue uses `journey.json` and its `.bak` backup in the game folder
  listed above.
- In-game host campaigns use `network-campaigns/<generated-id>.json` plus backups there.
  `network-campaign-connections.cfg` holds each client's private reconnect keys
  and the references used by **Resume hosted game**.
- A standalone host uses the exact `--save` path supplied. Relative paths are
  relative to the terminal's working directory. Without that option it uses
  `network-campaign.json` in the server user-data folder.

Close clients and stop the host before copying backups. Retain the host save/
backup and every participant's own connection file when moving a campaign.
Keep them private and out of source control. Copying only the server save cannot
recover lost client keys, and extracting a fresh ZIP does not reset player data.

Development shortcuts are available only when the launcher is given `--debug`.
Solo/local debug sessions keep progress/settings in memory and do not overwrite
normal saves. Network profile persistence and hosted-game resume are disabled
in debug mode; launch without `--debug` for ordinary campaign play and reconnect.
For a direct executable, pass game flags after `--`.

Simultaneous campaigns, internet matchmaking, human cooperative encounters and enhanced rendering are
future work. Report reproducible issues with the build identity, platform and
input method. Original-game fidelity and platform runtime checks are separate
from automated tests.
