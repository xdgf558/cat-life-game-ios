#!/usr/bin/env python3
"""Import only lossless alpha crops and the original coordinates manifest."""
import json
import re
import sys
from pathlib import Path

from PIL import Image


def main():
    source, catalog = map(Path, sys.argv[1:3])
    data = (source / "manifest.json").read_bytes()
    manifest = json.loads(data)
    assert manifest["formatVersion"] == 1 and manifest["assetCount"] == len(manifest["assets"]) == 105
    names = set()
    decoded_bytes = 0
    for record in manifest["assets"]:
        name = record["assetName"]
        assert re.fullmatch(r"(?:furniture-[a-z-]+|bowl-(?:empty|full))-(?:left|front|right)-(?:front|left|back|right)", name)
        assert name not in names
        names.add(name)
        assert record["fileName"] == name + ".png"
        rect = record["alphaBounds"]
        box = (rect["x"], rect["y"], rect["x"] + rect["width"], rect["y"] + rect["height"])
        with Image.open(source / record["fileName"]) as image:
            assert image.mode == "RGBA" and image.size == (1024, 1024)
            assert image.getchannel("A").getbbox() == box
            cropped = image.crop(box)
            destination = catalog / (name + ".imageset")
            destination.mkdir(parents=True, exist_ok=True)
            path = destination / record["fileName"]
            cropped.save(path, compress_level=9)
            with Image.open(path) as imported:
                assert imported.size == (rect["width"], rect["height"])
                assert imported.tobytes() == cropped.tobytes()
            decoded_bytes += cropped.width * cropped.height * 4
        contents = {"images": [{"filename": record["fileName"], "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
        (destination / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    dataset = catalog / "FurnitureArtwork68.dataset"
    dataset.mkdir(parents=True, exist_ok=True)
    (dataset / "manifest.json").write_bytes(data)
    contents = {"data": [{"filename": "manifest.json", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    (dataset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    assert (dataset / "manifest.json").read_bytes() == data
    print(f"Imported {len(names)} lossless alpha crops; {decoded_bytes:,} total decoded RGBA bytes; original manifest preserved byte-for-byte.")


if __name__ == "__main__":
    main()
