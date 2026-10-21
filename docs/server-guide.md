# Command-line host

The standalone host runs one classic campaign for up to four human knights, or
one practice duel for two game clients. It occupies no player slot. Campaigns
and duels each share the same authority used by their in-game hosting option.

Extract the whole local server ZIP. The Godot runtime is included; running it
requires neither a Godot editor nor Python. Linux and Windows server exports
have separate packages. Linux execution is tested; Windows execution remains
unverified.

## Get the server

Use a compatible local server ZIP or a versioned `server-v*` release when one is
available. Server packages are separate from asset-containing game packages.
Extract the whole ZIP, keeping its executable and launcher together. The
executable/archive names retain the earlier `Moonstone-Duel-Server` stem; the
`Moonstone-Server` launcher runs either mode.

If you have only the repository source, follow
[Build the server from source](#build-the-server-from-source). Each human also
needs a compatible game client; the server package does not include a game.

## Choose the mode

Run commands from a terminal in the extracted server directory. On Linux, make
`Moonstone-Server.sh` executable in file properties if extraction removed that
permission. On Windows, open Command Prompt in the extracted directory.

| Mode | Default UDP port | Human players | Launcher option |
| --- | --- | --- | --- |
| Classic campaign | 27867 | 1–4; computers fill the other seats | `--campaign --players 2` |
| Practice duel | 27866 | Exactly two | No mode option |

Keep the terminal open; Ctrl+C stops the host. It prints readiness and room-state
changes, plus final results for practice duels. Valid custom ports are 1024–65535.
The host runs without a game window, artwork or audio. These commands show its
options and independent version:

```bash
./Moonstone-Server.sh --help
./Moonstone-Server.sh --version
```

On Windows, use `Moonstone-Server.cmd` with the same options. That launcher uses
the included console wrapper.

## Host a campaign

```bash
./Moonstone-Server.sh --campaign --players 2 --save campaign.json
./Moonstone-Server.sh --campaign --players 4 --port 27867 --save friends.json
```

Windows example:

```bat
Moonstone-Server.cmd --campaign --players 2 --save campaign.json
```

Campaign mode uses UDP 27867 by default. `--players` accepts 1–4 humans; computer
knights fill the other seats. `--seed` optionally sets a new campaign's seed
from 1 through 2147483647. Existing saves retain their saved state and roster.
Each host process has one room. To run independent rooms, use separate processes,
ports and save paths.

Every human chooses **Network journey → Join journey** on the game's title
screen. Enter the host's address/port, choose a knight and join. All humans choose
Ready. Set `--players` to the number of humans who will join; the server uses no
seat. Classic turns, towns, monster fights and human knight duels use the same
rules as the in-game **Host new journey** option. Waiting players can browse
their own inventory while watching the active turn.

A missing human pauses the campaign and reserves their seat. Rejoining requires
the private connection key retained in that player's local game profile. All
humans choose Ready to resume. Retain the host save and each player's profile;
there is no remote seat-recovery administrator command in this first version.
The host stores credential hashes, not reusable client keys. Keep these local
files private and out of source control.

Reusing the same `--save` path loads the existing validated campaign, including
its human roster, and waits for those humans to reconnect. Changing `--players`
does not replace that saved roster. Use a new save filename for a new campaign.
An invalid primary tries its backup; two invalid copies prevent startup instead of silently replacing them.
The default save is `user://network-campaign.json` in the server's Godot user
data directory. A supplied relative path is relative to the server's working
directory. Network saves do not write the game's normal Continue file.

Commands and phase changes save progress; map travel also saves every two
seconds. Live reconnect resumes an exact paused fight while the host survives.
After a host process restart, existing safe-checkpoint rules return an unfinished
fight to its entrance. In-game **Resume hosted game** has the same disk behavior.
A stopped in-game host must be resumed by its owning player; there is no host
migration. Simultaneous campaign turns, multiple rooms within one process,
matchmaking and relays remain future work.

## Host a practice duel

```bash
./Moonstone-Server.sh --port 27866
```

On Windows: `Moonstone-Server.cmd --port 27866`.

Use compatible game and server builds. Both players choose **Practice → Network
duel**, enter the server computer's address and port, and choose **Join duel**.
The first accepted player gets seat one and the next gets seat two. Conflicting
knight colours are resolved automatically. Both choose **Ready** to start.

Each player controls its own knight with the usual controls. Both must agree to
a rematch. The host alone advances combat and validates input; both game clients
show replicas of that state. The in-game host player uses the same client path.

If either player leaves or loses the connection, the match ends for both. The
standalone host resets the room and keeps listening for a fresh pair. Both
players join again to start a new match. This is sequential reuse of one room;
practice live reconnection and simultaneous rooms remain later work. Campaigns
have the separate reserved-seat reconnect policy above.
The in-game **Host duel** option stops its owned host when that player leaves.

Duels do not use or alter campaign progress. Existing solo and local-party modes
remain separate. Network protocol 2 requires current matching clients; older
network-duel builds cannot join this host. Rules and game settings are unchanged.

## Addresses, backups and troubleshooting

- On another computer, use the host's LAN address. `127.0.0.1` connects to the
  same computer only. In-game hosting displays a local address in its lobby.
- Allow the chosen **UDP** port through the host's firewall. Internet hosting
  also requires a reachable host/router configuration; matchmaking, automatic
  router setup and relays are not provided.
- If Ready does not start play, every configured human must join and choose
  Ready. A saved campaign waits for its original human seats.
- If the port cannot open, check for another host using it. To run independent
  campaigns, use a different port and save file for each process.
- A build mismatch requires matching mode-specific gameplay code/data; equal
  displayed version numbers alone are insufficient. Obtain a matching client/
  server pair or rebuild both from the same gameplay source.
- For reserved-seat errors, retain each player's original game profile and
  reconnect to the intended room. Choosing the same knight colour alone cannot
  reclaim a seat. There is no administrator seat-reset command.
- Before moving or backing up a campaign, stop the host and retain its save and
  `.bak` file. Each human must also retain their own
  `network-campaign-connections.cfg`; a server save alone cannot recreate client
  reconnect keys. See [save locations](player-guide.md#save-locations-and-backups).
- If both save copies are invalid, preserve them for diagnosis. The host refuses
  to replace an unreadable campaign automatically.

Separate-machine campaign LAN and Internet play still need validation; local
UDP/fault tests are the current network evidence.


## Server versions and compatibility

The standalone server has its own version in `game/server/version.json` and a
separate release-tag namespace: `server-v0.1.0`, `server-v0.1.1`, and so on.
Its version does not have to equal the game version. Packaging and startup fixes
can ship independently; connecting still requires the same network protocol and
mode-specific code/rules fingerprint. A server version bump alone changes neither.

GitHub can hold game and server releases in the same repository. They share one
release list and one repository-wide latest-release designation. Server releases
should use their explicit tag and should not replace the latest game release.

The server needs no artwork or audio, but it does need numeric combat and
campaign tables. The reviewed tables are source files in the built-in [classic gameplay
pack](gameplay-packs.md). Clean GitHub-hosted builds use those exact definitions;
no private import, original disk image or substitute collision data is needed.

## Server releases

`.github/workflows/server-release.yml` runs only for pushed `server-v*` tags.
The tag must exactly match `game/server/version.json`, for example
`server-v0.1.0`; malformed tags and mismatched versions fail before tool downloads.
Prerelease versions such as `0.1.0-rc.1` produce prereleases. Game releases can use
a separate `game-v*` namespace and workflow; this server workflow does not build
or publish a game package.

The workflow downloads official Godot 4.6.1 archives with pinned SHA-512 checksums,
extracts only the required editor/templates, and stages an independent server
project/cache. It runs source/build-tool checks and asset-free exported Linux
server acceptance for two duel clients and four campaign clients (including
reserved-seat reconnect and saved-room restart), then prepares versioned
Linux/Windows ZIPs, manifests and SHA256SUMS. Windows execution and graphical-client acceptance are explicitly
outside this workflow. A separate job publishes only the allowlisted server
artifacts. Pinned Actions and read-only build permissions keep publication
permission confined to that final job.

Server releases use `--latest=false`, preserving the repository's latest game
release. Download a server by its explicit tag rather than `/releases/latest`.
Publishing still requires a deliberate tag push; local build commands neither
create tags nor publish releases.

## Build the server from source

The build currently runs on **Linux x86_64** and exports Linux and Windows
servers. Install Python 3.11+ and Git, and clone this repository. No game assets,
disk images, Python image libraries or offline import tools are required.

From the repository root, install the pinned official Godot 4.6.1 editor and
release templates, then configure the local shell and build:

```bash
python3 tools/install_server_toolchain.py
export GODOT_BIN="$PWD/work/server-toolchain/Godot_v4.6.1-stable_linux.x86_64"
export GODOT_TEMPLATES_DIR="$PWD/work/server-toolchain/templates"
python3 tools/server_release.py --tag server-v0.1.0
```

The installer downloads checksum-verified official archives into `work/` and
requires internet access. If you already have Godot 4.6.1 and matching release
templates, set those two variables to your existing locations instead. The
installer configures GitHub Actions automatically; in a local terminal the
explicit `export` commands above are required.

`server-v0.1.0` matches the current `game/server/version.json`; use the matching
tag argument if that file changes. The command builds, tests and packages into
`outputs/server-release/`, including Linux/Windows ZIPs and `SHA256SUMS`. It does
not create a Git tag or publish a release. The same complete build has been
rehearsed locally from a source copy without assets; the hosted workflow itself
has not yet been run.

Extract the chosen server ZIP and follow [Host a campaign](#host-a-campaign) or
[Host a practice duel](#host-a-practice-duel). Full game clients still require
their separately provisioned classic assets.
