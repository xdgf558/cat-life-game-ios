# Build 68 · original mesh furniture

Original procedural SceneKit meshes for CatLife 0.23.0 (68). This source generates the furniture itself in 3D, then renders each direction with the same orthographic camera and lighting rig. No image mirroring, perspective warping, downloaded models, external textures, or per-angle image generation is used. The handoff's `iso3d.js` was consulted for sizes and object parts only; none of its drawing code is used.

The established furniture assets are visual references for honey oak, sage fabric, cream rope, muted pink, and terracotta. Wood grain and fabric weave are deterministic original procedural textures. The four framed illustrations are original simple motifs drawn onto genuine thick, rounded 3D frames.

## Rendering contract

Every PNG is a full **1024 × 1024 RGBA** canvas at **160 pixels per world unit**. Images are never individually cropped, stretched, or mirrored. The shared origin is pixel **(512, 820)** measured from the top-left, or SpriteKit anchor **(0.5, 0.19921875)**. Floor furniture uses the footprint centre on the ground. Wall frames use the centre of the frame at that same origin, matching saved wall placement centres.

World axes are x right, y up, z toward the back wall. For floor objects, model front is −z; left is −x; back is +z; right is +x. Wall `facing` instead identifies the mounting surface, as described below. SceneKit receives `(x, y, −z)`. The three camera yaw angles are `left=48°`, `front=30°`, `right=12°`: a 30° base plus the app's ±18° view changes. Elevation is `asin(0.52)`, approximately 31.33°. Orthographic scale is 3.2 (half the 6.4-unit canvas height).

For world coordinates relative to the furniture origin, the pixel projection is:

```
screenX = 512 + 160 × (x cos(yaw) − z sin(yaw))
screenY = 820 − 160 × (0.52 × (x sin(yaw) + z cos(yaw)) + sqrt(1−0.52²) × y)
```

A fixed camera-relative upper-left warm key and broad ambient fill are reused for every model and facing. Materials have low specular response. There is **no ground mesh, shadow receiver, or baked contact shadow**. Runtime supplies the floor contact shadow. Transparent texture bounds must not be used as the hit area; use the model footprint or `alphaBounds` from validation.

## Outputs

Names are `furniture-{kebab-kind}-{view}-{facing}.png`. `view` is left/front/right. Floor facing follows the world directions above; wall facing identifies a wall surface.

| Models | Angles |
| --- | --- |
| cabinet, bookcase, cat-tree, rattan-chair | 3 views × 4 facings = 12 each |
| cat-bed, floor-cushion, flower-stool, plant, side-table | 3 views × front = 3 each; runtime reuses a view's image for other facings |
| bowl-empty, bowl-full | 3 views × front = 3 each; registered outlines and anchors |
| wall-cat, wall-flower, wall-sunrise, wall-town-memory | 3 views × front/left/right = 9 each |

Total: **105 PNGs**. The food bowl uses `bowl-empty-{view}-front.png` and `bowl-full-{view}-front.png`. The town memory frame uses the established Core prefix `furniture-town-memory-frame`, not the model's internal `wall-town-memory` label. For wall frames, `front` is a neutral thumbnail plane, `left` is the left wall's inward-facing surface, and `right` is the right wall's inward-facing surface. Wall decorations still do not expose player rotation in Core. All three surfaces show the actual single-sided illustration in every camera view.

The camera's front view has absolute yaw 30°. Wall plane angles are therefore measured relative to that camera normal, rather than reusing floor ±90° turns. In this rig, positive wall surface yaw points the normal toward screen right, so **left=+45°**, **right=−45°**, **front=0°**. This sign convention matches left-wall edges rising to the right and right-wall edges falling to the right. Actual SceneKit y-axis rotations are `modelYawDegrees = wallSurfaceYawDegrees − 30`, giving left +15°, right −75°, and neutral front −30°. This is why the signs differ from a floor-facing convention. For all camera yaws 12°/30°/48°, the art-plane normal's horizontal incidence is at least `cos(63°) > 0.45`; no backside drawing or double-sided material is used.

Floor meshes receive a true x/z scale before rendering: Core footprint width/depth divided by the design footprint. Heights retain the design values. Protruding handles, rounded rims and other mesh details remain physical geometry, so `actualModelDimensions` can exceed the placement footprint; it is the measured transformed mesh bounding box. Wall dimensions retain the design frame proportions because their Core hit rectangle is not a floor footprint. The bowl remains the design mesh and is calibrated against its existing display width at runtime.

| Kind | Core placement footprint (world units) | Design height |
| --- | --- | --- |
| cabinet | 186/128 × 78/64 | 1.5 |
| bookcase | 190/128 × 76/64 | 2.4 |
| cat-tree | 160/128 × 82/64 | 3.9 |
| cat-bed | 292/128 × 144/64 | 0.6 |
| floor-cushion | 154/128 × 80/64 | 0.3 |
| flower-stool | 126/128 × 68/64 | 0.95 |
| plant | 70/128 × 42/64 | 2.0 |
| rattan-chair | 158/128 × 88/64 | 1.9 |
| side-table | 136/128 × 72/64 | 1.2 |

The bed seat surface is y=0.44; entry points lie on the torus's top supporting surface at radius 0.74 and y=0.50, before x/z mesh scaling. Cushion centre is the ellipsoid top at y=0.2795; its entry points are on the actual ellipsoid surface at radius 0.78. Full-bowl food centre is the continuous food layer's top at y=0.1275; the empty state's corresponding centre is the bowl interior at y=0.12. These points receive the same node transform, facing and camera projection as the mesh. They are never inferred from rendered pixels.

## Manifest protocol (formatVersion 1)

The renderer writes `manifest.json` beside the PNGs. Top-level keys are:

- `formatVersion`: integer 1.
- `generator`: source identifier.
- `assetCount`: count of entries (105 for the full collection).
- `coordinateSystem`: world axes, pixel axes, cardinal direction meanings, and `wallFacingMeaning` explaining the separate wall-surface convention.
- `projection`: `type`, `canvasSize`, `pixelsPerUnit`, `anchorPixel`, `elevationSin`, `elevationDegrees`, `yawByView`, `wallReferenceCameraYawDegrees`, and `shadowReceiver`.
- `surfaceSemantics`: descriptions of seat, entry, and food reference surfaces.
- `assets`: array of per-image records described below.

Each asset record contains:

| Field | Meaning |
| --- | --- |
| `assetName` | Complete file stem, suitable as the image-set name. |
| `sourceAssetName` | Existing Core `metadata.assetName` prefix; bowls use `bowl-empty` or `bowl-full`. |
| `fileName` | PNG file name including extension. |
| `kind` | Core camelCase raw value, or `bowl`. |
| `state` | `default`, `empty`, or `full`. |
| `view`, `facing`, `yawDegrees` | The rendered room view, floor direction or wall surface, and camera yaw. |
| `wallSurfaceYawDegrees` | Required for walls: neutral 0, left +45, right −45 relative to the front-camera normal. Absent on floor and bowl records. |
| `modelYawDegrees` | Actual SceneKit y-axis mesh rotation; required for wall records. |
| `canvasSize` | `{width,height}` in pixels. |
| `alphaBounds` | `{x,y,width,height}` in top-left pixels, where right and bottom are exclusive. Computed from actual nonzero alpha. |
| `anchorPixel` | `{x,y}` in the same full-canvas pixel coordinates. |
| `anchorKind` | `footprintGroundCenter` or `wallMountCenter`. |
| `actualModelDimensions` | `{width,height,depth}` measured from the actual transformed mesh after scale and facing, along world x/y/z axes. |
| `footprintDimensions` | `{width,depth}` from Core, swapped for left/right facings; wall records are `null`; bowls reserve design footprint 1×1. |
| `modelScale` | Actual x/y/z scale applied before facing. |
| `surfacePixels` | Map of exact projected `{x,y}` points. Rest furniture has `seatCenter`, `frontEntrySurface`, `leftEntrySurface`, `backEntrySurface`, `rightEntrySurface`; bowls have `foodSurfaceCenter`; other kinds use an empty map. |
| `surfaceWorldPoints` | The same named points as transformed `{x,y,z}` world coordinates, for independent verification. |

All pixel fields use the original 1024 canvas. When importing a cropped image, subtract `alphaBounds.x/y` from both `anchorPixel` and every `surfacePixels` point, then normalize the cropped anchor for SpriteKit with `(x / cropWidth, 1 − y / cropHeight)`. Apply one uniform display scale to the cropped texture and all contact offsets; never independently stretch individual angles. Near-symmetric objects have only the rendered `front` image per view, so select their physical entry point by the named cardinal key from that reused image.

## Reproduce and verify

Requires the installed Xcode command-line tools, macOS SceneKit/Metal, and Python Pillow for the evidence sheets. No additional rendering package is needed. `render.sh` verifies that the required external volume is mounted before compiling. Its temporary files, compiler module cache, and executable all live in the designated external cache directory; it never falls back to local build caches. Swift 6.4.2 was observed to trap when `TMPDIR` contains the external volume's non-ASCII names, so the script uses a short ASCII symlink in `/private/tmp` pointing to the actual external temporary directory. It never creates a real local cache directory and refuses to overwrite an unexpected existing path.

```
./render.sh OUTPUT_DIRECTORY
# Optional single-model review:
./render.sh OUTPUT_DIRECTORY cabinet
# Update only wall surfaces, preserving existing floor/bowl PNGs and metadata:
./render.sh OUTPUT_DIRECTORY walls
python3 -B validate.py OUTPUT_DIRECTORY EVIDENCE_DIRECTORY
```

Partial renders merge their newly rendered records into an existing formatVersion-1 manifest and preserve all other asset records. The renderer asserts successful RGBA encoding, uniform dimensions, and front visibility of all wall surfaces. The validator asserts the exact 105-file matrix, transparent margins, no clipped meshes, Core placement dimensions, matching manifest alpha bounds, CPU-reprojected support points inside the mesh, registered empty/full bowl outlines, all wall surfaces facing the camera, and 12 distinct PNGs for each asymmetric model; it records SHA-256 and alpha bounds and creates fixed-scale per-model angle sheets and a collection overview. Visual review remains necessary for material appearance, room fit, and cat contact alignment.

## Runtime import

Only cropped PNGs and the original-coordinate manifest enter the app target. Keep the original 1024 renders and visual QA outside the repository. Import with:

```
python3 -B import_runtime.py EXTERNAL_PNG_DIRECTORY CatLife/Assets.xcassets
```

The importer verifies every alpha rectangle, compares decoded crop pixels losslessly, creates 105 image sets, and preserves the exact original manifest bytes in `FurnitureArtwork68.dataset`. The collection occupies 27,486,512 decoded RGBA bytes after cropping. `FurnitureArtwork68` reads that data once and gives each angle the same points-per-pixel ratio based on its kind's front/front alpha width. Its texture cache is bounded to 32 MiB and 48 entries.

`RoomFurnitureContact68` consumes the original CPU-projected surface points at runtime. It adjusts presentation only: a seat correction follows the actor's existing step progress; the meal's measured mean mouth point follows the food surface; clone-only lower-leg corrections compose the actor's existing warp. Source actions, source warp and saved placement coordinates remain unchanged. The actual cloned warp's Float vertices supply landmark corrections for rendered-point audits. The real-clock tests traverse the renderer subtree explicitly; SpriteKit's global `//` search must not be used to collect clone evidence.
