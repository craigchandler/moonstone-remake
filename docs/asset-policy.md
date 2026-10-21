# Asset and distribution policy

The public repository contains new source, resource definitions, offline import
code, documentation and numeric regression fixtures. It deliberately excludes:

- Original disk images, archives and extracted original files.
- Recovered or converted artwork, fonts, sounds, music and contact/media packs.
- Reference video, third-party source checkouts and downloaded tools.
- Personal builds, review reports, concept artwork and development/blog notes.
- Local assistant/editor configuration, saves and credentials.

`.gitignore` selects public docs/tools and keeps local asset families excluded.
`tools/check_public_tree.py` checks staged or committed objects for these paths,
media/binary files, common credential signatures and machine-specific paths.
It is a publication aid, not a legal review or a general secret scanner.

## Documentation screenshots

The selected images listed explicitly by `tools/check_public_tree.py` under
`docs/screenshots/` are documentation captures of the classic remake. This
exception covers those screenshots only. Runtime asset packs, sprite sheets,
fonts, original data, audio, footage and build packages remain excluded.

Screenshots contain original Moonstone artwork, which retains its respective
rights and is not covered by the source code's MIT licence. See the
[screenshot gallery](screenshots.md) and [attribution](../THIRD_PARTY.md).

## Source versus game content

The MIT licence applies to new source code. It does not relicense the original
Moonstone game or any separately owned or separately licensed material. The
original title, graphics, fonts, sounds, music, data and credits retain their
respective rights. Original runtime assets are not supplied by this repository.

A classic source checkout needs a compatible local native asset set or an
original-data import before it runs. Importing data does not transfer ownership
or grant redistribution permission. The game itself does not load disk images.

Keep assets local unless their publication is separately authorised and their
licensing is documented. New original artwork intended for public distribution
needs its own recorded provenance/licence and an explicit Git allowlist entry.
Do not place recovered assets in Git LFS, repository attachments or CI artifacts.

## Dependencies and builds

Optional import dependencies have separate licences, including noncommercial
terms. They are fetched separately rather than vendored or relicensed as MIT.
See [THIRD_PARTY.md](../THIRD_PARTY.md).

Local build tools generate engine/third-party notices using the matching Godot
editor and include them in personal packages. Packaging is local; it does not
publish a release, upload assets or create a remote repository. Public hosted
checks must remain source-only unless asset handling is separately arranged.

The reviewed numeric tables in `game/content/packs/classic/tables/` and
`game/content/packs/classic/campaign/` are an explicit source-content exception
to local generated inputs. They contain gameplay numbers and script references
only, including map travel, loot, quest rules and
the existing town dice clock. The dedicated server release workflow may
package these definitions with shared native code and Godot notices; it must not
include artwork, audio, original archives or other ignored generated resources.
This exception grants no rights to original media and does not relicense
original-derived data. See [gameplay packs](gameplay-packs.md).
