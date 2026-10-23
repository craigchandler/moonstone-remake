#!/bin/bash
# Executed by Westonpack after its graphics environment is ready.
# Keep quoted paths here, outside Westonpack's internally evaluated command.
if [ "${1:-}" = --prepare-content ]; then
    # Crusty's graphics preload prints to stdout in every dynamic executable.
    # Import tools and their headless children must run without that preload.
    unset LD_PRELOAD
fi
export XDG_DATA_HOME="$PWD/conf"
export XDG_CONFIG_HOME="$PWD/conf"
export XDG_CACHE_HOME="$PWD/cache"
godot_engine="/tmp/moonstone-godot/godot463.aarch64"
if [ -f "$PWD/cache/controller-mapping.txt" ]; then
    IFS= read -r SDL_GAMECONTROLLERCONFIG < "$PWD/cache/controller-mapping.txt"
    export SDL_GAMECONTROLLERCONFIG
fi
case "${SDL_GAMECONTROLLERCONFIG:-}" in
    19000000010000000100000000010000,Deeplay-keys,*)
        # muOS SDL2 counts three extra keys before the gamepad buttons. SDL3
        # (Godot 4.5+) numbers gamepad buttons first. Match the physical letters.
        # Source: MustardOS/internal, share/emulator/retroarch/autoconfig/udev/Deeplay-keys.cfg
        export SDL_GAMECONTROLLERCONFIG='19004ca6010000000100000000010000,RG40XX H,a:b0,b:b1,x:b3,y:b2,leftshoulder:b4,rightshoulder:b5,lefttrigger:b10,righttrigger:b11,guide:b8,start:b7,back:b6,dpup:h0.1,dpleft:h0.8,dpright:h0.2,dpdown:h0.4,leftx:a0,lefty:a1,leftstick:b9,rightx:a2,righty:a3,rightstick:b12,platform:Linux,'
        ;;
esac
printf 'Moonstone SDL3 mapping: %s\n' "${SDL_GAMECONTROLLERCONFIG:-default}"
# The code-only package includes a self-contained first-launch importer. Legacy
# private packages without importer.pck keep their embedded-content launch path.
if [ -f "$PWD/importer.pck" ]; then
    export MOONSTONE_GAME_DIR="$PWD"
    export PYTHONDONTWRITEBYTECODE=1
    export OPENBLAS_NUM_THREADS=1
    read -r importer_hash importer_archive < "$PWD/importer.sha256" || exit 1
    if [[ ! "$importer_hash" =~ ^[0-9a-f]{64}$ ]] || [ "$importer_archive" != importer.tar ]; then
        echo "Invalid importer checksum file. Reinstall the Moonstone package."
        exit 1
    fi
    export MOONSTONE_IMPORTER_DIR="$PWD/cache/importer-$importer_hash"
    importer_python="$MOONSTONE_IMPORTER_DIR/python/bin/python3.14"
    importer_driver="$MOONSTONE_IMPORTER_DIR/project/tools/portmaster_import.py"

    if [ "${1:-}" = --prepare-content ]; then
        # This worker starts only after the setup window exists. Its status file
        # covers archive checking/unpacking as well as the Python import stages.
        preparation_child=
        importer_temporary=
        preparation_error='Could not prepare import tools. See log.txt and reinstall the package.'
        preparation_status() {
            # All strings passed here are fixed messages, not filenames/input.
            printf '{"state":"%s","message":"%s","percent":%s}\n' "$1" "$2" "$3" > "$PWD/import-status.json.new"
            mv "$PWD/import-status.json.new" "$PWD/import-status.json"
        }
        preparation_cleanup() {
            if [ -n "$preparation_child" ]; then
                kill "$preparation_child" 2>/dev/null || true
                wait "$preparation_child" 2>/dev/null || true
            fi
            if [ -n "$importer_temporary" ]; then rm -rf -- "$importer_temporary"; fi
        }
        preparation_failed() {
            local result=$?
            trap - EXIT
            preparation_cleanup
            preparation_status failed "$preparation_error" 0
            exit "$result"
        }
        preparation_cancelled() {
            preparation_error='Import cancelled. Existing content and saves are unchanged.'
            exit 2
        }
        preparation_command() {
            "$@" &
            preparation_child=$!
            wait "$preparation_child"
            local result=$?
            preparation_child=
            return "$result"
        }
        trap preparation_failed EXIT
        trap preparation_cancelled TERM INT
        if [ ! -f "$MOONSTONE_IMPORTER_DIR/manifest.json" ]; then
            preparation_status running 'Checking import tools. Keep the device powered on.' 0
            preparation_command sha256sum -c "$PWD/importer.sha256" || exit 1
            importer_temporary=$(mktemp -d "$PWD/cache/importer-XXXXXX") || exit 1
            preparation_status running 'Unpacking import tools. This first step can take a little while.' 0
            # muOS BusyBox tar has no -z option; use the ordinary POSIX archive.
            preparation_command tar --no-same-owner -xf "$PWD/importer.tar" -C "$importer_temporary" || exit 1
            mv "$importer_temporary" "$MOONSTONE_IMPORTER_DIR" || exit 1
            importer_temporary=
        fi
        chmod +x "$importer_python" "$MOONSTONE_IMPORTER_DIR/bin/bake-audio" "$MOONSTONE_IMPORTER_DIR/bin/bake-menu" "$MOONSTONE_IMPORTER_DIR/bin/bake-module" || exit 1
        preparation_status running 'Starting original-disk conversion.' 0
        exec "$importer_python" -B "$importer_driver" --game-dir "$PWD" \
            --importer "$MOONSTONE_IMPORTER_DIR" --godot "${2:-$godot_engine}" "${@:3}"
        exit 1
    fi

    verified_content() {
        if [ ! -f "$MOONSTONE_IMPORTER_DIR/manifest.json" ]; then
            [ -f "$PWD/content/current.json" ] || return 1
            # A pack copied from a desktop needs neither disks nor unpacked
            # Python tools. The small setup runtime validates it directly.
            local checked
            checked=$(unset LD_PRELOAD; "$godot_engine" --headless --audio-driver Dummy \
                --main-pack "$PWD/importer.pck" -- --verify-content "$PWD") || return 1
            content_pack=$(unset LD_PRELOAD; printf '%s\n' "$checked" | sed -n 's/^CONTENT_PACK_PATH=//p')
            [[ -n "$content_pack" && "$content_pack" != *$'\n'* ]] && [ -f "$content_pack" ]
            return
        fi
        # Unset in the shell before Python starts: invoking an external env
        # command first would itself load Crusty and contaminate stdout.
        content_pack=$(unset LD_PRELOAD; "$importer_python" -B "$importer_driver" --game-dir "$PWD" --verify) || return 1
        [[ -n "$content_pack" && "$content_pack" != *$'\n'* ]] && [ -f "$content_pack" ]
    }
    if [ "${1:-}" = --verify-content ]; then
        verified_content || exit 1
        printf '%s\n' "$content_pack"
        exit 0
    fi
    if ! verified_content; then
        setup_result=0
        "$godot_engine" \
            --resolution "${DISPLAY_WIDTH:-640}x${DISPLAY_HEIGHT:-480}" --fullscreen \
            --rendering-method gl_compatibility --rendering-driver opengl3_es \
            --audio-driver Dummy --main-pack "$PWD/importer.pck" || setup_result=$?
        # The RG40XX H graphics runtime can abort while destroying its window,
        # after the worker has activated and checked the completed content.
        # Recover that shutdown failure only after independently rechecking the
        # pack. Explicit cancellation (2) and other failures remain failures.
        case "$setup_result" in 0|134) ;; *) exit "$setup_result" ;; esac
        if ! verified_content; then
            echo 'Original game content did not pass verification. See import.log.'
            [ "$setup_result" = 0 ] || exit "$setup_result"
            exit 1
        fi
        if [ "$setup_result" = 134 ]; then
            echo 'Setup window aborted on exit; completed content checksum verified. Starting Moonstone.'
        fi
    fi
    export MOONSTONE_CONTENT_PACK="$content_pack"
fi
exec "$godot_engine" \
    --resolution "${DISPLAY_WIDTH:-640}x${DISPLAY_HEIGHT:-480}" --fullscreen \
    --rendering-method gl_compatibility --rendering-driver opengl3_es \
    --audio-driver ALSA --main-pack "$PWD/moonstone.pck"
