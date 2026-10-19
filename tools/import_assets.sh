#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
if [[ ! -f "$task_root/game/assets/classic/knight/animations.tres" || ! -f "$task_root/game/content/generated/classic_collision.tres" ]]; then
  python3 "$task_root/tools/import_knight_animations.py"
fi
if [[ ! -f "$task_root/game/assets/classic/trogg_spear/animations.tres" || ! -f "$task_root/game/content/generated/spear_collision.tres" ]]; then
  python3 "$task_root/tools/import_spear_trogg.py"
fi
if [[ ! -f "$task_root/game/assets/classic/trogg_axe/animations.tres" || ! -f "$task_root/game/content/generated/axe_collision.tres" ]]; then
  python3 "$task_root/tools/import_axe_trogg.py"
fi
if [[ ! -f "$task_root/game/assets/classic/giant_troll/animations.tres" || ! -f "$task_root/game/content/generated/troll_collision.tres" ]]; then
  python3 "$task_root/tools/import_troll.py"
fi
if [[ ! -f "$task_root/game/assets/classic/hit_effects/animations.tres" ]]; then
  python3 "$task_root/tools/import_hit_effects.py"
fi
if [[ ! -f "$task_root/game/assets/classic/balok/animations.tres" || ! -f "$task_root/game/content/generated/balok_collision.tres" ]]; then
  python3 "$task_root/tools/import_balok.py"
fi
if [[ ! -f "$task_root/game/assets/classic/world/art.tres" ]] || ! rg -q '^moon_frames = ' "$task_root/game/assets/classic/world/art.tres"; then
  python3 "$task_root/tools/import_world_art.py"
fi
if [[ ! -f "$task_root/game/assets/classic/loot/single.png" || ! -f "$task_root/game/assets/classic/loot/font.png" || ! -f "$task_root/game/assets/classic/loot/cursor.png" || ! -f "$task_root/game/assets/classic/loot/art.tres" || ! -f "$task_root/game/content/generated/classic_loot.tres" ]]; then
  python3 "$task_root/tools/import_loot.py"
fi
if [[ ! -f "$task_root/game/assets/classic/guardian/animations.tres" || ! -f "$task_root/game/content/generated/original_lairs.json" ]]; then
  python3 "$task_root/tools/import_creature_pack.py"
fi
if [[ ! -f "$task_root/game/assets/classic/dragon_victim/animations.tres" || ! -f "$task_root/game/assets/classic/dragon/arena.png" ]] || ! rg -q 'execution_bite' "$task_root/game/assets/classic/dragon/animations.tres"; then
  python3 "$task_root/tools/import_creature_pack.py" --combat-corrections
fi
if ! rg -q 'tree_anchor' "$task_root/game/assets/classic/ratman/animations.tres" || ! rg -q 'ejected' "$task_root/game/assets/classic/war_beast/animations.tres"; then
  python3 "$task_root/tools/import_creature_pack.py" --tree-beast
fi
if ! rg -q 'fallen_front' "$task_root/game/assets/classic/war_beast/animations.tres"; then
  python3 "$task_root/tools/import_beast_frames.py"
fi
if [[ ! -f "$task_root/game/content/generated/classic_map_travel.tres" ]]; then
  python3 "$task_root/tools/import_map_travel.py"
fi
if [[ ! -f "$task_root/game/assets/classic/guardian_finishes/animations.tres" ]]; then
  python3 "$task_root/tools/import_finishes.py"
fi
if ! python3 - "$task_root" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])/'game/assets/classic'
families=['death_knight','spear_finishes','balok_finishes','mud_finishes','guardian_finishes','dragon','dragon_victim','ratman']
try:
    valid=all(json.loads((root/f/'provenance.json').read_text()).get('frame_paths_version')==(2 if f=='death_knight' else 3) for f in families)
except (OSError,ValueError):valid=False
sys.exit(0 if valid else 1)
PY
then
  python3 "$task_root/tools/import_death_frames.py"
  python3 "$task_root/tools/import_audio.py"
fi
if ! python3 - "$task_root" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])/'game/assets/classic'
try:
    valid=all(json.loads((root/f/'provenance.json').read_text()).get('hit_paths_version')==1 for f in ['trogg_hammer','ratman','knight_finishes'])
except (OSError,ValueError):valid=False
sys.exit(0 if valid else 1)
PY
then
  python3 "$task_root/tools/import_hit_recovery.py"
  python3 "$task_root/tools/import_audio.py"
fi
if [[ ! -f "$task_root/game/assets/classic/audio/sounds.tres" ]]; then
  python3 "$task_root/tools/import_audio.py"
fi
if [[ ! -f "$task_root/game/content/generated/knockback.tres" ]]; then
  python3 "$task_root/tools/import_knockback.py"
fi
if ! python3 - "$task_root" <<'PYGUARD'
import json,sys
from pathlib import Path
try:valid=json.loads((Path(sys.argv[1])/'game/assets/classic/guardian_finishes/provenance.json').read_text()).get('guardian_paths_version')==1
except (OSError,ValueError):valid=False
sys.exit(0 if valid else 1)
PYGUARD
then
  python3 "$task_root/tools/import_guardian_timing.py"
  python3 "$task_root/tools/import_audio.py"
fi
if [[ ! -f "$task_root/game/assets/classic/stonehenge/art.tres" ]]; then
  python3 "$task_root/tools/import_stonehenge.py"
fi
if ! rg -q 'ritual_open' "$task_root/game/assets/classic/audio/sounds.tres"; then
  python3 "$task_root/tools/import_audio.py"
fi
if [[ ! -f "$task_root/game/content/generated/moonstone_quest.tres" ]]; then
  python3 "$task_root/tools/import_moonstone_quest.py"
fi
if ! rg -q 'moonstone_full' "$task_root/game/assets/classic/loot/art.tres"; then
  python3 "$task_root/tools/import_loot.py"
fi
if ! rg -q 'retail hunk4:239' "$task_root/game/assets/classic/world/provenance.json"; then
  python3 "$task_root/tools/import_world_art.py"
fi
if [[ ! -f "$task_root/game/assets/classic/ending_opening/art.tres" ]]; then
  python3 "$task_root/tools/import_ending_opening.py"
fi
if ! rg -q '"rat_tree_version": 1' "$task_root/game/assets/classic/ratman/provenance.json"; then
  python3 "$task_root/tools/import_ratman_tree.py"
fi
if ! rg -q '"33": ExtResource'  "$task_root/game/assets/classic/world/art.tres"; then
  python3 "$task_root/tools/import_map_locations.py"
fi
if [[ ! -f "$task_root/game/assets/classic/intro_menu/art.tres" ]]; then
  python3 "$task_root/tools/import_intro_menu.py"
fi
if [[ ! -f "$task_root/game/assets/classic/targeted_scrolls/black_life.png" ]]; then
  python3 "$task_root/tools/import_targeted_scrolls.py"
fi
if [[ ! -f "$task_root/game/assets/classic/town_locations/art.tres" ]]; then
  python3 "$task_root/tools/import_town_locations.py"
fi
if [[ ! -f "$task_root/game/assets/classic/ending_complete/art.tres" ]]; then
  python3 "$task_root/tools/import_ending_complete.py"
fi
if [[ ! -f "$task_root/game/assets/classic/knight_selection/art.tres" ]]; then
  python3 "$task_root/tools/import_knight_selection.py"
fi
if [[ ! -f "$task_root/game/content/generated/classic_beast_entry.tres" ]]; then
  python3 "$task_root/tools/import_beast_entries.py"
fi
if ! python3 - "$task_root" <<'PYTROGG'
import json,sys
from pathlib import Path
r=Path(sys.argv[1])/'game/assets/classic'
try:ok=all(json.loads((r/k/'provenance.json').read_text()).get('trogg_timing_version')==1 for k in ['trogg_axe','trogg_hammer'])
except (OSError,ValueError):ok=False
sys.exit(0 if ok else 1)
PYTROGG
then
  python3 "$task_root/tools/import_trogg_timing.py"
fi
if ! python3 - "$task_root" <<'PYMONSTER'
import json,sys
from pathlib import Path
r=Path(sys.argv[1])/'game/assets/classic'
try:ok=all(json.loads((r/k/'provenance.json').read_text()).get('monster_timing_version')==1 for k in ['giant_troll','ratman','dragon','guardian'])
except (OSError,ValueError):ok=False
sys.exit(0 if ok else 1)
PYMONSTER
then
  python3 "$task_root/tools/import_monster_timing.py"
fi
if ! python3 "$task_root/tools/import_classic_layers.py" --check; then
  python3 "$task_root/tools/import_classic_layers.py"
fi
