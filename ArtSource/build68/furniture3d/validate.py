#!/usr/bin/env python3
"""Validate the original mesh renders and make fixed-scale visual evidence."""
import hashlib
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

KINDS = ["cabinet", "bookcase", "cat-tree", "cat-bed", "floor-cushion", "flower-stool", "plant", "rattan-chair", "side-table", "bowl-empty", "bowl-full", "wall-cat", "wall-flower", "wall-sunrise", "wall-town-memory"]
ASYMMETRIC = {"cabinet", "bookcase", "cat-tree", "rattan-chair"}
VIEWS = ["left", "front", "right"]
FACINGS = ["front", "left", "back", "right"]
YAW = {"left": 48, "front": 30, "right": 12}
FLOOR_DIMENSIONS = {"cabinet": (186 / 128, 78 / 64), "bookcase": (190 / 128, 76 / 64),
                    "cat-tree": (160 / 128, 82 / 64), "cat-bed": (292 / 128, 144 / 64),
                    "floor-cushion": (154 / 128, 80 / 64), "flower-stool": (126 / 128, 68 / 64),
                    "plant": (70 / 128, 42 / 64), "rattan-chair": (158 / 128, 88 / 64),
                    "side-table": (136 / 128, 72 / 64)}


def asset_base(kind):
    return kind if kind.startswith("bowl-") else "furniture-town-memory-frame" if kind == "wall-town-memory" else f"furniture-{kind}"


def facings_for(kind):
    return FACINGS if kind in ASYMMETRIC else ["front", "left", "right"] if kind.startswith("wall-") else ["front"]


def main():
    source, evidence = map(Path, sys.argv[1:3])
    evidence.mkdir(parents=True, exist_ok=True)
    expected = {f"{asset_base(kind)}-{view}-{facing}.png" for kind in KINDS for view in VIEWS for facing in facings_for(kind)}
    assert len(expected) == 105
    actual = {p.name for p in source.glob("*.png")}
    assert actual == expected, {"missing": sorted(expected - actual), "extra": sorted(actual - expected)}
    manifest = json.loads((source / "manifest.json").read_text())
    assert manifest["formatVersion"] == 1 and manifest["assetCount"] == 105
    assert manifest["coordinateSystem"]["wallFacingMeaning"]
    assert manifest["projection"]["wallReferenceCameraYawDegrees"] == 30
    metadata = {a["fileName"]: a for a in manifest["assets"]}
    assert set(metadata) == expected and len(metadata) == len(manifest["assets"])
    records = []
    for name in sorted(expected):
        path = source / name
        entry = metadata[name]
        assert entry["assetName"] == name[:-4]
        assert name.startswith(entry["sourceAssetName"] + "-")
        assert entry["canvasSize"] == {"width": 1024, "height": 1024}
        assert entry["anchorPixel"] == {"x": 512, "y": 820}
        assert entry["yawDegrees"] == YAW[entry["view"]]
        assert all(math.isfinite(v) and v > 0 for v in entry["actualModelDimensions"].values())
        assert entry["anchorKind"] == ("wallMountCenter" if entry["kind"].startswith("wall") else "footprintGroundCenter")
        if entry["kind"].startswith("wall"):
            assert entry["wallSurfaceYawDegrees"] == {"front": 0, "left": 45, "right": -45}[entry["facing"]]
            assert math.isclose(entry["modelYawDegrees"], entry["wallSurfaceYawDegrees"] - 30, abs_tol=1e-8)
            assert math.cos(math.radians(entry["yawDegrees"] + entry["modelYawDegrees"])) > 0.45, (name, "wall art front faces away")
        with Image.open(path) as im:
            assert im.size == (1024, 1024) and im.mode == "RGBA", name
            alpha = im.getchannel("A")
            bounds = alpha.getbbox()
            assert bounds and min(bounds) > 2 and max(bounds) < 1022, (name, bounds)
            assert alpha.getpixel((0, 0)) == alpha.getpixel((512, 1023)) == 0, name
            x, y, right, bottom = bounds
            assert entry["alphaBounds"] == {"x": x, "y": y, "width": right - x, "height": bottom - y}, name
            points = entry["surfaceWorldPoints"]
            assert set(points) == set(entry["surfacePixels"])
            for surface, point in points.items():
                a = math.radians(entry["yawDegrees"])
                px = 512 + 160 * (point["x"] * math.cos(a) - point["z"] * math.sin(a))
                py = 820 - 160 * (0.52 * (point["x"] * math.sin(a) + point["z"] * math.cos(a)) + math.sqrt(1 - 0.52 ** 2) * point["y"])
                rendered = entry["surfacePixels"][surface]
                assert math.isclose(px, rendered["x"], abs_tol=1e-6) and math.isclose(py, rendered["y"], abs_tol=1e-6), (name, surface)
                assert alpha.getpixel((round(px), round(py))) > 0, (name, surface, "projected support point is outside the model")
            records.append({"file": name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "alphaBounds": bounds, "bytes": path.stat().st_size})
    for kind in ASYMMETRIC:
        unique = {r["sha256"] for r in records if r["file"].startswith(f"{asset_base(kind)}-")}
        assert len(unique) == 12, (kind, "angles must be independent 3D renders")
    for kind in KINDS:
        facings = facings_for(kind)
        cell_w, cell_h = 320, 360
        sheet = Image.new("RGB", (cell_w * len(facings), cell_h * 3), "#f5ecd9")
        d = ImageDraw.Draw(sheet)
        # One union crop for every angle of this model preserves registration and scale.
        bounds = [r["alphaBounds"] for r in records if r["file"].startswith(f"{asset_base(kind)}-")]
        union = (min(b[0] for b in bounds) - 24, min(b[1] for b in bounds) - 24, max(b[2] for b in bounds) + 24, max(b[3] for b in bounds) + 24)
        factor = min(288 / (union[2] - union[0]), 288 / (union[3] - union[1]))
        for row, view in enumerate(VIEWS):
            for col, facing in enumerate(facings):
                name = f"{asset_base(kind)}-{view}-{facing}.png"
                entry = metadata[name]
                if kind in FLOOR_DIMENSIONS:
                    w, depth = FLOOR_DIMENSIONS[kind]
                    if facing in {"left", "right"}:
                        w, depth = depth, w
                    assert entry["footprintDimensions"] == {"width": w, "depth": depth}, name
                required = {"seatCenter", "frontEntrySurface", "leftEntrySurface", "backEntrySurface", "rightEntrySurface"} if kind in {"cat-bed", "floor-cushion"} else {"foodSurfaceCenter"} if kind.startswith("bowl-") else set()
                assert set(entry["surfacePixels"]) == required, name
                with Image.open(source / name) as im:
                    tile = im.crop(union)
                    tile = tile.resize((round(tile.width * factor), round(tile.height * factor)), Image.Resampling.LANCZOS)
                    sheet.paste(tile, (col * cell_w + (cell_w - tile.width) // 2, row * cell_h + 40 + (288 - tile.height) // 2), tile)
                d.text((col * cell_w + 10, row * cell_h + 8), f"{kind} / {view} / {facing}", fill="#685039")
                d.text((col * cell_w + 10, row * cell_h + 340), f"yaw {YAW[view]} / true mesh / fixed origin", fill="#8a745d")
        sheet.save(evidence / f"{kind}-angles.png")
    for view in VIEWS:
        empty = metadata[f"bowl-empty-{view}-front.png"]
        full = metadata[f"bowl-full-{view}-front.png"]
        assert empty["alphaBounds"] == full["alphaBounds"] and empty["actualModelDimensions"] == full["actualModelDimensions"]
        assert hashlib.sha256((source / empty["fileName"]).read_bytes()).digest() != hashlib.sha256((source / full["fileName"]).read_bytes()).digest()
    overview = Image.new("RGB", (1750, 1260), "#f5ecd9")
    d = ImageDraw.Draw(overview)
    for index, kind in enumerate(KINDS):
        col, row = index % 5, index // 5
        with Image.open(source / f"{asset_base(kind)}-front-front.png") as im:
            tile = im.crop((200, 170, 824, 970)).resize((312, 400), Image.Resampling.LANCZOS)
            overview.paste(tile, (col * 350 + 19, row * 420 + 16), tile)
        d.text((col * 350 + 15, row * 420 + 10), kind, fill="#685039")
    overview.save(evidence / "all-models-front.png")
    contacts = Image.new("RGB", (1280, 1080), "#f5ecd9")
    cd = ImageDraw.Draw(contacts)
    palette = {"seatCenter": ("S", "#d25176"), "frontEntrySurface": ("F", "#187c63"), "leftEntrySurface": ("L", "#4d78a7"),
               "backEntrySurface": ("B", "#9470aa"), "rightEntrySurface": ("R", "#b9802b"), "foodSurfaceCenter": ("C", "#d25176")}
    for col, kind in enumerate(["cat-bed", "floor-cushion", "bowl-empty", "bowl-full"]):
        entries = [metadata[f"{asset_base(kind)}-{v}-front.png"] for v in VIEWS]
        bounds = [a["alphaBounds"] for a in entries]
        crop = (min(b["x"] for b in bounds) - 24, min(b["y"] for b in bounds) - 24,
                max(b["x"] + b["width"] for b in bounds) + 24, max(b["y"] + b["height"] for b in bounds) + 24)
        factor = min(288 / (crop[2] - crop[0]), 288 / (crop[3] - crop[1]))
        for row, a in enumerate(entries):
            with Image.open(source / a["fileName"]) as im:
                tile = im.crop(crop).resize((round((crop[2] - crop[0]) * factor), round((crop[3] - crop[1]) * factor)), Image.Resampling.LANCZOS)
                ox, oy = col * 320 + (320 - tile.width) // 2, row * 360 + 42 + (288 - tile.height) // 2
                contacts.paste(tile, (ox, oy), tile)
            cd.text((col * 320 + 10, row * 360 + 8), f"{kind} / {a['view']} / projected mesh points", fill="#685039")
            for name, point in a["surfacePixels"].items():
                label, fill = palette[name]
                px, py = ox + (point["x"] - crop[0]) * factor, oy + (point["y"] - crop[1]) * factor
                cd.ellipse((px - 4, py - 4, px + 4, py + 4), fill=fill, outline="#ffffff")
                cd.text((px + 6, py - 7), label, fill=fill)
            cd.text((col * 320 + 10, row * 360 + 340), "S seat; F/L/B/R entry; C food centre", fill="#8a745d")
    contacts.save(evidence / "contact-surfaces.png")
    report = {"result": "passed", "count": len(records), "size": [1024, 1024], "pixelsPerUnit": 160,
              "anchorPixelsTopLeft": [512, 820], "spriteKitAnchor": [0.5, 0.19921875],
              "worldAxes": "x right, y up, z toward back wall; front=-z,left=-x,back=+z,right=+x",
              "cameraYawDegrees": YAW, "cameraElevationSin": 0.52, "shadowReceiver": False, "files": records}
    (evidence / "asset-validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Passed: {len(records)} RGBA PNGs; Core footprints, metadata, CPU-projected support points, empty/full registration, transparent margins and independent angles; contact sheets written.")


if __name__ == "__main__":
    main()
