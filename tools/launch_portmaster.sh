#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
elif [ -d "/mnt/mmc/MUOS/PortMaster/" ]; then
    controlfolder="/mnt/mmc/MUOS/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt" || exit 1
[ -f "$controlfolder/mod_${CFW_NAME}.txt" ] && source "$controlfolder/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/${directory#/}/ports/moonstone"
if [ ! -f "$GAMEDIR/moonstone.pck" ]; then
    GAMEDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/moonstone"
fi
cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

BINARY=godot463.aarch64
weston_dir=/tmp/weston
godot_dir=/tmp/moonstone-godot
weston_mounted=0
godot_mounted=0
weston_started=0
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    [ "$weston_started" = 1 ] && $ESUDO "$weston_dir/westonwrap.sh" cleanup
    if [ "${PM_CAN_MOUNT:-Y}" != N ]; then
        [ "$godot_mounted" = 1 ] && $ESUDO umount "$godot_dir"
        [ "$weston_mounted" = 1 ] && $ESUDO umount "$weston_dir"
    fi
    pm_finish
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$DEVICE_ARCH" != aarch64 ]; then
    pm_show_error "Moonstone requires 64-bit ARM firmware (aarch64)." --title Moonstone
    exit 1
fi

echo "Moonstone: device=$DEVICE_NAME firmware=$CFW_NAME arch=$DEVICE_ARCH"
mkdir -p "$GAMEDIR/conf" "$GAMEDIR/cache" || exit 1
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
# Restore the mapping after Westonpack configures its environment.
printf '%s\n' "$SDL_GAMECONTROLLERCONFIG" > "$GAMEDIR/cache/controller-mapping.txt" || exit 1

for runtime in weston_pkg_0.2 godot_4.6.3; do
    if [ ! -s "$controlfolder/libs/$runtime.squashfs" ]; then
        pm_message "Installing $runtime. Please wait." --title Moonstone
        if ! $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "$runtime.squashfs" ||
                [ ! -s "$controlfolder/libs/$runtime.squashfs" ]; then
            pm_show_error "Install Godot 4.6.3 and Westonpack 0.2 through PortMaster's Runtime Manager, then try again." --title "Runtime unavailable"
            exit 1
        fi
    fi
done

$ESUDO mkdir -p "$weston_dir" "$godot_dir" || exit 1
if [ "${PM_CAN_MOUNT:-Y}" != N ]; then
    $ESUDO umount "$weston_dir" 2>/dev/null
    $ESUDO umount "$godot_dir" 2>/dev/null
fi
$ESUDO mount "$controlfolder/libs/weston_pkg_0.2.squashfs" "$weston_dir" || exit 1
weston_mounted=1
$ESUDO mount "$controlfolder/libs/godot_4.6.3.squashfs" "$godot_dir" || exit 1
godot_mounted=1

runner=moonstone-run
[ -f "$runner" ] || runner=moonstone-run.sh
case "${1:-}" in
    --import-content)
        rm -f "$GAMEDIR/import-cancel"
        bash "./$runner" --prepare-content "$godot_dir/$BINARY" "${@:2}"; exit $? ;;
    --verify-content) bash "./$runner" --verify-content; exit $? ;;
    '') ;;
    *) pm_show_error "Usage: Moonstone.sh [--import-content [--force] | --verify-content]" --title Moonstone; exit 2 ;;
esac

if [ -z "$GPTOKEYB2" ]; then
    pm_show_error "Update PortMaster to install the gptokeyb2 exit helper." --title Moonstone
    exit 1
fi
# Godot reads the controller; gptokeyb2 supplies only Select + Start.
$GPTOKEYB2 "$BINARY" > /dev/null 2>&1 &
pm_platform_helper "$godot_dir/$BINARY"
weston_started=1
# Native controller input must remain enabled.
$ESUDO env CRUSTY_BLOCK_INPUT=0 "$weston_dir/westonwrap.sh" headless noop kiosk crusty_x11egl \
    bash "./$runner"
