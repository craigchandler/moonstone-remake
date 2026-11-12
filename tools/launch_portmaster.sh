#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
    controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
    controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
    controlfolder="$XDG_DATA_HOME/PortMaster"
else
    controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt" || exit 1
[ -f "$controlfolder/mod_${CFW_NAME}.txt" ] && source "$controlfolder/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/moonstone"
godot_runtime=godot_4.6.3
godot_executable="godot463.$DEVICE_ARCH"
weston_runtime=weston_pkg_0.2
weston_dir=/tmp/weston
godot_dir=/tmp/godot

cd "$GAMEDIR" || exit 1
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
mkdir -p "$GAMEDIR/conf" "$GAMEDIR/cache" || exit 1

# Install runtimes before mounting either one.
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
    if [ ! -f "$controlfolder/harbourmaster" ]; then
        pm_message "This port requires the latest PortMaster. Please update PortMaster."
        pm_finish
        exit 1
    fi
    $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${weston_runtime}.squashfs" || { pm_finish; exit 1; }
fi
if [ ! -f "$controlfolder/libs/${godot_runtime}.squashfs" ]; then
    if [ ! -f "$controlfolder/harbourmaster" ]; then
        pm_message "This port requires the latest PortMaster. Please update PortMaster."
        pm_finish
        exit 1
    fi
    $ESUDO "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${godot_runtime}.squashfs" || { pm_finish; exit 1; }
fi

$ESUDO mkdir -p "$weston_dir" "$godot_dir" || exit 1
if [ "$PM_CAN_MOUNT" != N ]; then
    $ESUDO umount "$weston_dir" 2>/dev/null
    $ESUDO umount "$godot_dir" 2>/dev/null
fi
result=1
if $ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "$weston_dir" &&
        $ESUDO mount "$controlfolder/libs/${godot_runtime}.squashfs" "$godot_dir"; then
    # Godot reads the controller; gptokeyb2 supplies only Select + Start.
    $GPTOKEYB2 "$godot_executable" > /dev/null 2>&1 &
    pm_platform_helper "$godot_dir/$godot_executable"
    # Prepare player-supplied content and native input in Weston's environment.
    $ESUDO env CRUSTY_BLOCK_INPUT=0 MOONSTONE_CONTROLLER="$sdl_controllerconfig" \
        "$weston_dir/westonwrap.sh" headless noop kiosk crusty_x11egl \
        '. ./moonstone-setup &&' "$godot_dir/$godot_executable" \
        --resolution "${DISPLAY_WIDTH}x${DISPLAY_HEIGHT}" -f \
        --rendering-driver opengl3_es --audio-driver ALSA --main-pack moonstone.pck
    result=$?
fi

$ESUDO "$weston_dir/westonwrap.sh" cleanup
if [ "$PM_CAN_MOUNT" != N ]; then
    $ESUDO umount "$weston_dir"
    $ESUDO umount "$godot_dir"
fi
pm_finish
exit "$result"
