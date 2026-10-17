#!/usr/bin/env python3
"""Decode user-owned AmigaDOS IPFs and extract files; never alter the originals.

CAPS handles preservation-track decoding. This tool checks AmigaDOS sector
checksums, directory checksums and file chains before writing extracted data.
Standard 80-cylinder, double-sided, 11-sector OFS disks are supported.
MFM format reference: Keir Fraser's public-domain Disk-Utilities/amigados.c.
"""
from __future__ import annotations
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import struct

U32 = C.c_uint32
I32 = C.c_int32
BLOCK = 512

class Track(C.Structure):
    _layout_ = "ms"  # SPS ABI explicitly uses byte packing on every host
    _pack_ = 1
    _fields_ = [(n, U32) for n in ("type", "cylinder", "head", "sector_count", "sector_size")]
    _fields_ += [("buffer", C.c_void_p), ("length", U32), ("timing_length", U32),
                 ("timing", C.c_void_p), ("overlap", I32)]

def be32(data: bytes, offset: int = 0) -> int:
    return struct.unpack_from(">I", data, offset)[0]

def odd_even(data: bytes) -> bytes:
    half = len(data) // 2
    if half % 4:
        raise ValueError("unaligned MFM data")
    return b"".join(struct.pack(">I", ((be32(data, i) & 0x55555555) << 1)
                               | (be32(data, half + i) & 0x55555555))
                    for i in range(0, half, 4))

def sector_checksum(data: bytes) -> int:
    value = 0
    for offset in range(0, len(data), 4):
        value ^= be32(data, offset)
    return ((value >> 1) ^ value) & 0x55555555

def sectors_from_track(raw: bytes, track_number: int) -> list[bytes]:
    bits = "".join(f"{byte:08b}" for byte in raw)
    bits += bits[:9000]  # a sector may wrap across the index position
    sync = f"{0x44894489:032b}"
    sectors: dict[int, bytes] = {}
    position = 0
    while len(sectors) < 11:
        found = bits.find(sync, position)
        if found < 0 or found >= len(raw) * 8:
            break
        position = found + 1
        start = found + 32
        body_bits = bits[start:start + 1080 * 8]
        if len(body_bits) != 1080 * 8:
            continue
        body = int(body_bits, 2).to_bytes(1080, "big")
        info = odd_even(body[:8])
        label = odd_even(body[8:40])
        if info[0] != 255 or info[1] != track_number or info[2] >= 11:
            continue
        payload = odd_even(body[56:1080])
        if sector_checksum(info + label) != be32(odd_even(body[40:48])):
            continue
        if sector_checksum(payload) != be32(odd_even(body[48:56])):
            continue
        sector = info[2]
        if sector in sectors and sectors[sector] != payload:
            raise ValueError(f"track {track_number}: conflicting sector {sector}")
        sectors[sector] = payload
    if len(sectors) != 11:
        raise ValueError(f"track {track_number}: only {len(sectors)}/11 verified sectors")
    return [sectors[i] for i in range(11)]

def decode_ipf(path: Path, library: Path, files_only: bool = False) -> tuple[bytes, list[int]]:
    cap = C.CDLL(str(library.resolve()))
    signatures = {
        "CAPSInit": [], "CAPSExit": [], "CAPSAddImage": [],
        "CAPSRemImage": [I32], "CAPSLockImage": [I32, C.c_char_p],
        "CAPSUnlockImage": [I32], "CAPSLoadImage": [I32, U32],
        "CAPSLockTrack": [C.POINTER(Track), I32, U32, U32, U32],
        "CAPSUnlockTrack": [I32, U32, U32],
    }
    for name, types in signatures.items():
        function = getattr(cap, name)
        function.argtypes = types
        function.restype = I32
    if cap.CAPSInit() != 0:
        raise ValueError("CAPS initialisation failed")
    image = cap.CAPSAddImage()
    if image < 0:
        cap.CAPSExit()
        raise ValueError("CAPS image allocation failed")
    try:
        if cap.CAPSLockImage(image, str(path.resolve()).encode()) != 0:
            raise ValueError(f"CAPS cannot open {path.name}")
        if cap.CAPSLoadImage(image, 0) != 0:
            raise ValueError(f"CAPS cannot decode {path.name}")
        output = bytearray()
        omitted = []
        for number in range(160):
            cylinder, head = divmod(number, 2)
            track = Track()
            track.type = 1
            # Revision-one track structure, deterministic track data.
            flags = (1 << 9) | (1 << 13)
            rc = cap.CAPSLockTrack(C.byref(track), image, cylinder, head, flags)
            if rc != 0 or not track.buffer or not 8000 <= track.length <= 100000:
                raise ValueError(f"track {number}: invalid CAPS result {rc}, length {track.length}")
            raw = C.string_at(track.buffer, track.length)
            try:
                output.extend(b"".join(sectors_from_track(raw, number)))
            except ValueError:
                # These retail images use a non-AmigaDOS protection track at 1.
                # File-only extraction may ignore it if no directory/file block
                # references it. Any other missing or corrupt track stays fatal.
                if not files_only or number != 1 or f"{0x44894489:032b}" in "".join(f"{b:08b}" for b in raw):
                    raise
                output.extend(bytes(11 * BLOCK))
                omitted.append(number)
            cap.CAPSUnlockTrack(image, cylinder, head)
        return bytes(output), omitted
    finally:
        cap.CAPSUnlockImage(image)
        cap.CAPSRemImage(image)
        cap.CAPSExit()

def extract_ofs(image: bytes, omitted_tracks: list[int] | None = None) -> dict[str, bytes]:
    if len(image) != 901120 or image[:3] != b"DOS" or image[3] & 1:
        raise ValueError("expected a standard AmigaDOS OFS disk")
    used = set()
    output: dict[str, bytes] = {}
    def block(number: int, kind: int | None = None) -> bytes:
        if number // 11 in (omitted_tracks or []):
            raise ValueError(f"filesystem references omitted preservation track at block {number}")
        if not 2 <= number < 1760 or number in used:
            raise ValueError(f"cyclic, overlapping or invalid block {number}")
        used.add(number)
        data = image[number * BLOCK:(number + 1) * BLOCK]
        if sum(struct.unpack(">128I", data)) & 0xffffffff:
            raise ValueError(f"block {number}: checksum mismatch")
        if kind is not None and be32(data) != kind:
            raise ValueError(f"block {number}: unexpected type")
        return data
    def directory(number: int, prefix: str = "") -> None:
        directory_block = block(number, 2)
        for slot in range(72):
            header = be32(directory_block, 24 + slot * 4)
            while header:
                h = block(header, 2)
                length = h[432]
                if not 1 <= length <= 30:
                    raise ValueError("invalid filename length")
                name = h[433:433 + length].decode("latin-1")
                if name in (".", "..") or any(c in name for c in "/\\\0"):
                    raise ValueError("unsafe filename")
                target = prefix + name
                subtype = struct.unpack_from(">i", h, 508)[0]
                if subtype == 2:
                    # The header is also the subdirectory table; release for traversal.
                    used.remove(header)
                    directory(header, target + "/")
                elif subtype == -3:
                    size, next_block = be32(h, 324), be32(h, 16)
                    if size > len(image):
                        raise ValueError(f"{target}: invalid size")
                    content = bytearray()
                    sequence = 1
                    while next_block:
                        d = block(next_block, 8)
                        count = be32(d, 12)
                        if be32(d, 4) != header or be32(d, 8) != sequence:
                            raise ValueError(f"{target}: owner/sequence mismatch")
                        if not 1 <= count <= 488 or len(content) + count > size:
                            raise ValueError(f"{target}: invalid payload length")
                        content.extend(d[24:24 + count])
                        next_block = be32(d, 16)
                        sequence += 1
                    if len(content) != size or target in output:
                        raise ValueError(f"{target}: incomplete or duplicate file")
                    extension = be32(h, 504)
                    while extension:
                        e = block(extension, 16)
                        if struct.unpack_from(">i", e, 508)[0] != -3:
                            raise ValueError(f"{target}: invalid extension header")
                        extension = be32(e, 504)
                    output[target] = bytes(content)
                else:
                    raise ValueError(f"{target}: unsupported directory entry {subtype}")
                header = be32(h, 496)
    directory(880)
    return output

def main() -> None:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--caps-library", type=Path,
                        default=root / "work/upstream/capsimg/capsimg.so")
    parser.add_argument("--out", type=Path, default=root / "reference/extracted")
    parser.add_argument("--adf-out", type=Path, help="optional temporary images for reference-port testing")
    parser.add_argument("--files-only", action="store_true", help="allow unreferenced non-AmigaDOS track 1; not a complete preservation conversion")
    args = parser.parse_args()
    records = []
    # Validate every disk before writing output.
    results = [(path, *decode_ipf(path, args.caps_library, args.files_only)) for path in args.images]
    parsed = [(path, image, omitted, extract_ofs(image, omitted)) for path, image, omitted in results]
    if args.out.exists() and any(args.out.iterdir()):
        raise ValueError("output already contains files; choose a fresh directory")
    args.out.mkdir(parents=True, exist_ok=True)
    disk_records = []
    for path, image, omitted, files in parsed:
        disk_id = path.stem.rsplit("Disk", 1)[-1]
        if disk_id not in ("A", "B", "C"):
            raise ValueError(f"cannot identify source disk {path.name}")
        for name, content in files.items():
            target = args.out / disk_id / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            records.append({"disk": disk_id, "file": name, "size": len(content),
                            "sha256": hashlib.sha256(content).hexdigest()})
        if args.adf_out:
            args.adf_out.mkdir(parents=True, exist_ok=True)
            (args.adf_out / f"Disk{ord(disk_id) - ord('A') + 1}.adf").write_bytes(image)
        disk_records.append({"disk": disk_id, "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                             "verified_sectors": (160 - len(omitted)) * 11, "omitted_nonfilesystem_tracks": omitted})
        print(f"Disk {disk_id}: {(160 - len(omitted)) * 11} verified sectors, {len(files)} verified files; omitted nonfilesystem tracks: {omitted}")
    (args.out / "manifest.json").write_text(json.dumps({"schema": 1, "disks": disk_records, "files": records}, indent=2) + "\n")
    print(f"PASS: {len(records)} files imported; source images unchanged")

if __name__ == "__main__":
    main()
