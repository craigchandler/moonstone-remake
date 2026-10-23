#!/bin/bash
# Moonstone's native controller adapter uses PortMaster's SDL mapping.
# Westonpack supplies the X11/EGL environment; gameplay remains in moonstone.pck.
case "${1:-}" in ''|--import-content|--verify-content) ;; *) echo 'Usage: Moonstone.sh [--import-content [--force] | --verify-content]'; exit 2 ;; esac
launcher_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
for candidate in /mnt/mmc/MUOS/PortMaster /opt/system/Tools/PortMaster /opt/tools/PortMaster "$XDG_DATA_HOME/PortMaster" /roms/ports/PortMaster; do
    if [ -f "$candidate/control.txt" ]; then
        controlfolder=$candidate
        break
    fi
done
if [ -z "${controlfolder:-}" ]; then
    echo "PortMaster was not found. Install/update PortMaster for your firmware first."
    exit 1
fi
source "$controlfolder/control.txt" || exit 1
if [ -f "$controlfolder/mod_${CFW_NAME}.txt" ]; then
    source "$controlfolder/mod_${CFW_NAME}.txt" || exit 1
fi
get_controls
# Standard PortMaster installs keep these together. muOS relocates launchers to
# roms/PORTS while keeping game data in the SD card's ports directory.
GAMEDIR="$launcher_dir/moonstone"
if [ ! -f "$GAMEDIR/moonstone.pck" ]; then
    GAMEDIR="/${directory#/}/ports/moonstone"
fi
if [ ! -f "$GAMEDIR/moonstone.pck" ]; then
    pm_message "Missing moonstone/moonstone.pck beside the launcher or in this SD card's ports directory. See moonstone/README.txt."
    exit 1
fi
cd "$GAMEDIR" || exit 1
runner=moonstone-run
# Retain compatibility with the earlier private/manual packages.
if [ ! -f "$runner" ]; then runner=moonstone-run.sh; fi
if [ ! -f "$runner" ]; then
    pm_message "Missing Moonstone launch helper. Reinstall the package."
    exit 1
fi
exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "Moonstone PortMaster: device=${DEVICE_NAME:-unknown}, firmware=${CFW_NAME:-unknown}, arch=${DEVICE_ARCH:-unknown}"
if [ "${DEVICE_ARCH:-}" != aarch64 ]; then
    pm_message "This Moonstone package requires aarch64. Other architectures are not included."
    exit 1
fi
CONFDIR="$GAMEDIR/conf"
mkdir -p "$CONFDIR" "$GAMEDIR/cache" || exit 1
export SDL_GAMECONTROLLERCONFIG="${sdl_controllerconfig:-${SDL_GAMECONTROLLERCONFIG:-}}"
# Restore this after Westonpack's shell/environment setup. Keep raw mapping
# text out of its internally evaluated command (names can contain spaces).
printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" > "$GAMEDIR/cache/controller-mapping.txt" || exit 1

ensure_runtime() {
    local filename=$1
    if [ ! -s "$controlfolder/libs/$filename" ]; then
        if [ ! -f "$controlfolder/harbourmaster" ]; then
            pm_message "Update PortMaster and install Godot 4.6.3 and Westonpack 0.2 through its Runtime Manager before playing offline."
            return 1
        fi
        $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "$filename" || return 1
    fi
    [ -s "$controlfolder/libs/$filename" ]
}
ensure_runtime weston_pkg_0.2.squashfs || exit 1
ensure_runtime godot_4.6.3.squashfs || exit 1

weston_dir=/tmp/weston
godot_dir=/tmp/moonstone-godot
weston_mounted=0
godot_mounted=0
weston_started=0
mapper_pid=
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    if [ "$weston_started" = 1 ]; then
        $ESUDO "$weston_dir/westonwrap.sh" cleanup
    fi
    if [ -n "$mapper_pid" ]; then kill "$mapper_pid" 2>/dev/null || true; fi
    if [ "${PM_CAN_MOUNT:-Y}" != N ]; then
        if [ "$godot_mounted" = 1 ]; then $ESUDO umount "$godot_dir"; fi
        if [ "$weston_mounted" = 1 ]; then $ESUDO umount "$weston_dir"; fi
    fi
    pm_finish
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
$ESUDO mkdir -p "$weston_dir" "$godot_dir" || exit 1
if [ "${PM_CAN_MOUNT:-Y}" != N ]; then
    $ESUDO umount "$weston_dir" 2>/dev/null || true
    $ESUDO umount "$godot_dir" 2>/dev/null || true
fi
$ESUDO mount "$controlfolder/libs/weston_pkg_0.2.squashfs" "$weston_dir" || exit 1
weston_mounted=1
$ESUDO mount "$controlfolder/libs/godot_4.6.3.squashfs" "$godot_dir" || exit 1
godot_mounted=1
if [ ! -x "$godot_dir/godot463.aarch64" ] || [ ! -x "$weston_dir/westonwrap.sh" ]; then
    pm_message "Runtime is incomplete or the wrong architecture. Reinstall the ARM64 runtimes."
    exit 1
fi
if [ "${1:-}" = --import-content ]; then
    rm -f "$GAMEDIR/import-cancel"
    bash "./$runner" --prepare-content "$godot_dir/godot463.aarch64" "${@:2}"
    exit $?
fi
if [ "${1:-}" = --verify-content ]; then
    bash "./$runner" --verify-content
    exit $?
fi
# No key mapping: Godot handles both sticks, context-sensitive buttons and pause.
# gptokeyb supplies only the usual PortMaster exit hotkey (Select + Start).
if [ -z "${GPTOKEYB:-}" ]; then
    pm_message "PortMaster controller helper is missing. Update PortMaster first."
    exit 1
fi
if [ ! -f "$GAMEDIR/moonstone.gptk" ]; then
    pm_message "Missing Moonstone native-input configuration. Reinstall the game ZIP."
    exit 1
fi
$GPTOKEYB godot463.aarch64 -c "$GAMEDIR/moonstone.gptk" &
mapper_pid=$!
pm_platform_helper "$godot_dir/godot463.aarch64"
weston_started=1
# Use relative paths: Westonpack's wrapper constructs a shell command internally.
# Keep native gamepad input enabled and forward SDL's per-device mapping.
$ESUDO env CRUSTY_BLOCK_INPUT=0 "$weston_dir/westonwrap.sh" headless noop kiosk crusty_x11egl \
    bash "./$runner"
exit $?
