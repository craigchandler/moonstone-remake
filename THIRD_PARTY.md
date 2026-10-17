# Attribution and third-party material

The MIT licence covers the new source code in this repository. The following
projects/material have separate ownership and terms. They are not relicensed
by this repository.

## Original game

Moonstone: A Hard Day’s Knight (1991) and its title, artwork, fonts, music,
sounds, executable/data and original credits belong to their respective rights
holders. The public tree contains no original game package or recovered media.
Locally imported scenes retain the original credits. This unofficial remake is
not an endorsement or affiliation.

## Runtime engine

[Godot Engine](https://github.com/godotengine/godot) is MIT licensed and includes
third-party components under their respective licences. The local packaging
step obtains the matching editor’s engine/third-party notices and includes them
with personal builds. Godot source or binaries are not vendored here.

## Offline references and import dependencies

| Project | Use | Terms/source |
| --- | --- | --- |
| [Moonstone ACE](https://github.com/Jarskih/moonstone-ace-public) | Reference behavior; separately fetched hunk/art readers and offline sound/music helpers | [PolyForm Noncommercial 1.0.0](https://github.com/Jarskih/moonstone-ace-public/blob/f0d699a2b92d42d5380429ea9f2d94f7534324ef/LICENSE) |
| [Moonstone 2026](https://github.com/Undine1/Moonstone-A-Hard-Days-Knight-2026) | Earlier reference investigation | Separate upstream terms; no vendored code or runtime dependency |
| [CAPSImg](https://github.com/FrodeSolheim/capsimg) | Optional owned-IPF decoding during offline extraction | [SPS decoder licence](https://github.com/FrodeSolheim/capsimg/blob/ed4cb0912fb1a2a0d5203111c6f6abd50d411b56/LICENCE.txt), including noncommercial restrictions |
| [Disk-Utilities](https://github.com/keirf/disk-utilities) | AmigaDOS MFM format reference for the new extractor | Inspect the referenced source’s own notices; no decoder code vendored |
| [Pillow](https://github.com/python-pillow/Pillow) | Optional offline image conversion | Separate upstream licence |
| [NumPy](https://github.com/numpy/numpy) | Optional offline conversion calculations | Separate upstream licence |

Exact revisions and the development engine identity are recorded in
[docs/upstream-sources.json](docs/upstream-sources.json). Dependencies remain in
local ignored checkouts/environments. Optional import/synthesis tools can use
separately licensed code; the Godot gameplay core does not embed it or emulate
Amiga hardware. The MIT source licence does not remove those dependencies’
restrictions or grant redistribution rights to generated game content.

Do not copy upstream source or media into the public tree without retaining
its notices, documenting provenance and confirming a compatible scope.
