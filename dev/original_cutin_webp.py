"""Reuse artists' WebP streams in the isolated mobile export's imported textures."""
from hashlib import md5
from io import BytesIO
from pathlib import Path
import re
import struct

from PIL import Image


def compact(project: Path) -> int:
    """Keep Godot's imported texture metadata and replace identical pixels' larger encoding."""
    saved = 0
    for source in sorted((project / "art/cutins").glob("*.webp")):
        remap = source.with_suffix(".webp.import").read_text(encoding="utf-8")
        relative = re.search(r'^path="res://(\.godot/imported/[^"/]+\.ctex)"$', remap, re.M)
        if relative is None:
            raise ValueError(f"Missing imported texture for {source.name}")
        texture = project / relative[1]
        contents = texture.read_bytes()
        webp = source.read_bytes()

        # GST2 v1, one RGB8 WebP payload, no mip levels. Fail on unknown layouts.
        if not (contents[:4] == b"GST2" and len(contents) >= 68
                and struct.unpack_from("<I", contents, 4)[0] == 1
                and struct.unpack_from("<I", contents, 36)[0] == 2
                and struct.unpack_from("<III", contents, 44) == (0, 4, len(contents) - 56)
                and contents[56:60] == b"RIFF" and contents[64:68] == b"WEBP"):
            raise ValueError(f"Unexpected imported layout for {source.name}")
        if len(webp) >= len(contents) - 56:
            continue
        with Image.open(BytesIO(contents[56:])) as imported, Image.open(BytesIO(webp)) as original:
            if (imported.size != original.size
                    or original.convert("RGBA").tobytes() != imported.convert("RGBA").tobytes()):
                raise ValueError(f"Original and imported pixels differ in {source.name}")

        compacted = contents[:52] + struct.pack("<I", len(webp)) + webp
        stamp = texture.with_suffix(".md5")
        status = stamp.read_text(encoding="ascii")
        old = f'dest_md5="{md5(contents).hexdigest()}"'
        if status.count(old) != 1:
            raise ValueError(f"Unexpected import stamp for {source.name}")
        texture.write_bytes(compacted)
        stamp.write_text(status.replace(old, f'dest_md5="{md5(compacted).hexdigest()}"'), encoding="ascii")
        saved += len(contents) - len(compacted)
    return saved


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staged_project", type=Path)
    args = parser.parse_args()
    print("Identical WebP pixels. Bytes saved:", compact(args.staged_project))
