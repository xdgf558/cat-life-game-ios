// Build 68 original procedural meshes. World x right, z back, y up; SceneKit z = -world z.
import AppKit
import SceneKit
import Metal

let fm = FileManager.default
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let requested = CommandLine.arguments.dropFirst(2).first
try fm.createDirectory(at: output, withIntermediateDirectories: true)
let side = 1024
let pixelsPerUnit: CGFloat = 160
let groundPixelY: CGFloat = 820
let elevation = asin(0.52)
let views: [(String, Double)] = [("left", 48), ("front", 30), ("right", 12)]
let facings: [(String, Double)] = [("front", 0), ("left", -.pi / 2), ("back", .pi), ("right", .pi / 2)]
let allKinds = ["cabinet", "bookcase", "cat-tree", "cat-bed", "floor-cushion", "flower-stool", "plant", "rattan-chair", "side-table", "bowl-empty", "bowl-full", "wall-cat", "wall-flower", "wall-sunrise", "wall-town-memory"]
let asymmetric: Set<String> = ["cabinet", "bookcase", "cat-tree", "rattan-chair"]
// Left/right mean visible wall surfaces, with inward normals toward screen right/left.
let wallSurfaceYaw: [String: Double] = ["front": 0, "left": 45, "right": -45]
let wallReferenceCameraYaw = 30.0
let floorDimensions: [String: (width: Double, depth: Double, authoredWidth: Double, authoredDepth: Double)] = [
    "cabinet": (186 / 128, 78 / 64, 2, 1), "bookcase": (190 / 128, 76 / 64, 2, 1),
    "cat-tree": (160 / 128, 82 / 64, 2, 2), "cat-bed": (292 / 128, 144 / 64, 2, 2),
    "floor-cushion": (154 / 128, 80 / 64, 2, 2), "flower-stool": (126 / 128, 68 / 64, 1, 1),
    "plant": (70 / 128, 42 / 64, 1, 1), "rattan-chair": (158 / 128, 88 / 64, 2, 2),
    "side-table": (136 / 128, 72 / 64, 1, 1)
]

func assetBase(_ kind: String) -> String {
    if kind.hasPrefix("bowl-") { return kind }
    return kind == "wall-town-memory" ? "furniture-town-memory-frame" : "furniture-\(kind)"
}
func coreKind(_ kind: String) -> String {
    if kind.hasPrefix("bowl-") { return "bowl" }
    let parts = kind.split(separator: "-")
    return String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
}

func authoredSurfaces(_ kind: String) -> [String: SCNVector3] {
    if kind == "cat-bed" {
        return ["seatCenter": SCNVector3(0, 0.44, 0),
            "frontEntrySurface": SCNVector3(0, 0.50, -0.74), "leftEntrySurface": SCNVector3(-0.74, 0.50, 0),
            "backEntrySurface": SCNVector3(0, 0.50, 0.74), "rightEntrySurface": SCNVector3(0.74, 0.50, 0)]
    }
    if kind == "floor-cushion" {
        let edge = 0.78, surfaceY = 0.14 + 0.93 * 0.15 * sqrt(1 - pow(edge / 0.93, 2))
        return ["seatCenter": SCNVector3(0, 0.14 + 0.93 * 0.15, 0),
            "frontEntrySurface": SCNVector3(0, surfaceY, -edge), "leftEntrySurface": SCNVector3(-edge, surfaceY, 0),
            "backEntrySurface": SCNVector3(0, surfaceY, edge), "rightEntrySurface": SCNVector3(edge, surfaceY, 0)]
    }
    if kind.hasPrefix("bowl-") {
        return ["foodSurfaceCenter": SCNVector3(0, kind == "bowl-full" ? 0.1275 : 0.12, 0)]
    }
    return [:]
}

func pointRecord(_ point: SCNVector3) -> [String: Double] {
    ["x": Double(point.x), "y": Double(point.y), "z": Double(point.z)]
}
func projectedPixel(_ point: SCNVector3, _ yaw: Double) -> [String: Double] {
    let a = yaw * .pi / 180, x = Double(point.x), y = Double(point.y), z = Double(point.z)
    return ["x": 512 + 160 * (x * cos(a) - z * sin(a)),
            "y": 820 - 160 * (0.52 * (x * sin(a) + z * cos(a)) + cos(elevation) * y)]
}
func worldPoint(_ local: SCNVector3, _ node: SCNNode) -> SCNVector3 {
    let scn = node.convertPosition(SCNVector3(local.x, local.y, -local.z), to: nil)
    return SCNVector3(scn.x, scn.y, -scn.z)
}
func actualDimensions(_ node: SCNNode) -> [String: Double] {
    let (lo, hi) = node.boundingBox
    var minPoint = SCNVector3(Double.infinity, Double.infinity, Double.infinity)
    var maxPoint = SCNVector3(-Double.infinity, -Double.infinity, -Double.infinity)
    for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] {
        let p = node.convertPosition(SCNVector3(x, y, z), to: nil)
        minPoint.x = min(minPoint.x, p.x); minPoint.y = min(minPoint.y, p.y); minPoint.z = min(minPoint.z, p.z)
        maxPoint.x = max(maxPoint.x, p.x); maxPoint.y = max(maxPoint.y, p.y); maxPoint.z = max(maxPoint.z, p.z)
    } } }
    return ["width": Double(maxPoint.x - minPoint.x), "height": Double(maxPoint.y - minPoint.y), "depth": Double(maxPoint.z - minPoint.z)]
}
func alphaBounds(_ bitmap: NSBitmapImageRep) -> [String: Int] {
    precondition(!bitmap.isPlanar && bitmap.bitsPerSample == 8 && bitmap.samplesPerPixel == 4)
    let alphaIndex = bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : 3
    let bytes = bitmap.bitmapData!
    var minX = side, minY = side, maxX = -1, maxY = -1
    for y in 0..<side { for x in 0..<side where bytes[y * bitmap.bytesPerRow + x * 4 + alphaIndex] > 0 {
        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
    } }
    precondition(minX > 2 && minY > 2 && maxX < side - 3 && maxY < side - 3)
    return ["x": minX, "y": minY, "width": maxX - minX + 1, "height": maxY - minY + 1]
}

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func texture(_ hex: Int, _ kind: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 512, height: 512))
    image.lockFocus()
    color(hex).setFill(); NSRect(x: 0, y: 0, width: 512, height: 512).fill()
    if kind == "wood" {
        for i in 0..<210 {
            let y = Double(i) * 2.47
            let p = NSBezierPath(); p.lineWidth = i % 6 == 0 ? 1.2 : 0.55
            color(i % 3 == 0 ? 0x855322 : 0xFFF0CA, i % 6 == 0 ? 0.12 : 0.08).setStroke()
            p.move(to: NSPoint(x: 0, y: y))
            for x in stride(from: 8, through: 520, by: 8) {
                let offset = sin(Double(x) * 0.022 + Double(i) * 0.67) * 2.2
                p.line(to: NSPoint(x: Double(x), y: y + offset))
            }
            p.stroke()
        }
    } else if kind == "cloth" {
        for i in stride(from: 0, to: 512, by: 3) {
            color(0xFFFAEC, 0.08).setStroke()
            let p = NSBezierPath(); p.lineWidth = 0.6
            p.move(to: NSPoint(x: i, y: 0)); p.line(to: NSPoint(x: i, y: 512)); p.stroke()
            color(0x574D35, 0.055).setStroke()
            let q = NSBezierPath(); q.lineWidth = 0.6
            q.move(to: NSPoint(x: 0, y: i)); q.line(to: NSPoint(x: 512, y: i)); q.stroke()
        }
    }
    image.unlockFocus()
    return image
}

var materials: [String: SCNMaterial] = [:]
func material(_ hex: Int, _ tex: String = "") -> SCNMaterial {
    let key = "\(hex)-\(tex)"
    if let existing = materials[key] { return existing }
    let m = SCNMaterial()
    m.lightingModel = .blinn
    m.diffuse.contents = tex.isEmpty ? color(hex) : texture(hex, tex)
    m.specular.contents = color(0x15110B)
    m.shininess = 0.045
    m.roughness.contents = 0.98
    m.isDoubleSided = false
    materials[key] = m
    return m
}
let wood = material(0xDEA05C, "wood"), woodLight = material(0xEABD80, "wood")
let woodDark = material(0xB78148, "wood"), wicker = material(0xD3A469, "wood")
let cream = material(0xF5E7C9, "cloth"), sage = material(0xA9BA79, "cloth")
let pink = material(0xE9B0BC, "cloth"), rope = material(0xE8CE9E, "cloth")
let green = material(0x78A770), terra = material(0xD88C67)

@discardableResult func box(_ parent: SCNNode, _ x: Double, _ y: Double, _ z: Double,
    _ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial, _ radius: Double = 0.035) -> SCNNode {
    let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(radius, min(w, min(h, d)) * 0.4))
    g.chamferSegmentCount = 4; g.materials = [m]
    let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, -z)
    parent.addChildNode(n); return n
}
@discardableResult func cylinder(_ parent: SCNNode, _ x: Double, _ y: Double, _ z: Double,
    _ r: Double, _ h: Double, _ m: SCNMaterial) -> SCNNode {
    let g = SCNCylinder(radius: r, height: h); g.radialSegmentCount = 64; g.materials = [m]
    let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, -z); parent.addChildNode(n); return n
}
@discardableResult func sphere(_ parent: SCNNode, _ x: Double, _ y: Double, _ z: Double,
    _ r: Double, _ m: SCNMaterial, _ scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
    let g = SCNSphere(radius: r); g.segmentCount = 40; g.materials = [m]
    let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, -z); n.scale = scale
    parent.addChildNode(n); return n
}
@discardableResult func torus(_ parent: SCNNode, _ x: Double, _ y: Double, _ z: Double,
    _ ring: Double, _ pipe: Double, _ m: SCNMaterial) -> SCNNode {
    let g = SCNTorus(ringRadius: ring, pipeRadius: pipe)
    g.ringSegmentCount = 64; g.pipeSegmentCount = 12; g.materials = [m]
    let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, -z); parent.addChildNode(n); return n
}
func rod(_ parent: SCNNode, _ a: SCNVector3, _ b: SCNVector3, _ r: Double, _ m: SCNMaterial) {
    let va = SIMD3<Double>(Double(a.x), Double(a.y), -Double(a.z))
    let vb = SIMD3<Double>(Double(b.x), Double(b.y), -Double(b.z))
    let delta = vb - va, length = simd_length(delta)
    let g = SCNCylinder(radius: r, height: length); g.radialSegmentCount = 12; g.materials = [m]
    let n = SCNNode(geometry: g); n.simdPosition = SIMD3<Float>((va + vb) / 2)
    n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(delta / length))
    parent.addChildNode(n)
}
func feet(_ parent: SCNNode, _ x: Double, _ z: Double, _ height: Double, _ r: Double = 0.095) {
    for sx in [-1.0, 1.0] { for sz in [-1.0, 1.0] {
        cylinder(parent, sx * x, height / 2, sz * z, r, height, woodDark)
    } }
}
func ropePost(_ parent: SCNNode, _ x: Double, _ z: Double, _ bottom: Double, _ height: Double, _ r: Double) {
    cylinder(parent, x, bottom + height / 2, z, r, height, rope)
    for y in stride(from: bottom + 0.035, to: bottom + height, by: 0.062) {
        torus(parent, x, y, z, r - 0.006, 0.018, rope)
    }
}

func illustration(_ kind: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 512, height: 512)); image.lockFocus()
    color(kind == "wall-flower" ? 0xF8E1DF : kind == "wall-sunrise" ? 0xD7EAF0 : 0xF5ECD6).setFill()
    NSRect(x: 0, y: 0, width: 512, height: 512).fill()
    if kind == "wall-cat" {
        color(0xDCA15B).setFill()
        NSBezierPath(ovalIn: NSRect(x: 107, y: 115, width: 298, height: 258)).fill()
        let ears = NSBezierPath()
        ears.move(to: NSPoint(x: 125, y: 295)); ears.line(to: NSPoint(x: 135, y: 440)); ears.line(to: NSPoint(x: 235, y: 360)); ears.close()
        ears.move(to: NSPoint(x: 277, y: 360)); ears.line(to: NSPoint(x: 377, y: 440)); ears.line(to: NSPoint(x: 390, y: 295)); ears.close(); ears.fill()
        color(0xFFF1D8).setFill()
        for x in [197, 307] { NSBezierPath(ovalIn: NSRect(x: x - 9, y: 235, width: 18, height: 28)).fill() }
    } else if kind == "wall-flower" {
        color(0x7FA579).setStroke(); let stem = NSBezierPath(); stem.lineWidth = 12
        stem.move(to: NSPoint(x: 256, y: 105)); stem.line(to: NSPoint(x: 256, y: 285)); stem.stroke()
        color(0xDA95A3).setFill()
        for i in 0..<6 { let a = Double(i) * .pi / 3; NSBezierPath(ovalIn: NSRect(x: 211 + cos(a) * 77, y: 265 + sin(a) * 77, width: 90, height: 90)).fill() }
        color(0xE7BE6D).setFill(); NSBezierPath(ovalIn: NSRect(x: 214, y: 268, width: 84, height: 84)).fill()
    } else {
        color(0xEDBF6E).setFill(); NSBezierPath(ovalIn: NSRect(x: 182, y: 241, width: 150, height: 150)).fill()
        for (i, c) in [0xACBF8E, 0x7EAB8B, 0x72958A].enumerated() {
            color(c).setFill(); NSBezierPath(ovalIn: NSRect(x: -150 + i * 150, y: -110 - i * 12, width: 550, height: 350)).fill()
        }
        if kind == "wall-town-memory" {
            for (i, c) in [0xE2B579, 0xD2A18E, 0xE8C79D].enumerated() {
                color(c).setFill(); NSRect(x: 103 + i * 112, y: 145, width: 83, height: 107).fill()
                color(0xA7795D).setFill(); let roof = NSBezierPath(); let x = 96 + i * 112
                roof.move(to: NSPoint(x: x, y: 252)); roof.line(to: NSPoint(x: x + 48, y: 302)); roof.line(to: NSPoint(x: x + 96, y: 252)); roof.close(); roof.fill()
            }
        }
    }
    image.unlockFocus(); return image
}

func model(_ kind: String) -> SCNNode {
    let p = SCNNode(); p.name = kind
    switch kind {
    case "cabinet":
        feet(p, 0.79, 0.31, 0.24)
        box(p, 0, 0.8, 0, 1.86, 1.14, 0.86, wood, 0.055)
        box(p, 0, 1.415, 0, 2, 0.17, 1, woodLight, 0.07)
        for y in [0.535, 1.075] {
            box(p, 0, y, -0.458, 1.64, 0.48, 0.095, woodLight, 0.045)
            cylinder(p, 0, y, -0.545, 0.054, 0.14, woodDark).eulerAngles.x = .pi / 2
            sphere(p, 0, y, -0.602, 0.082, woodLight, SCNVector3(1, 1, 0.65))
        }
        box(p, 0, 0.80, 0.44, 1.61, 0.91, 0.03, woodDark, 0.012)
    case "bookcase":
        feet(p, 0.81, 0.31, 0.16, 0.075)
        box(p, 0, 1.24, 0.4, 1.92, 2.19, 0.12, woodDark)
        for x in [-0.92, 0.92] { box(p, x, 1.24, 0, 0.16, 2.2, 0.9, wood) }
        for y in [0.19, 0.91, 1.63, 2.34] { box(p, 0, y, -0.01, 2.04, 0.12, 1, woodLight) }
        let palette = [0xC88588, 0x7694A1, 0xDDC077, 0x8EA77E, 0xA48AA9]
        for shelf in 0..<3 {
            var x = -0.73
            for i in 0..<5 {
                let h = 0.39 + Double((i + shelf) % 3) * 0.065, w = 0.14 + Double(i % 2) * 0.035
                let b = box(p, x, 0.27 + Double(shelf) * 0.72 + h / 2, -0.105, w, h, 0.48, material(palette[(i + shelf) % palette.count], "cloth"), 0.012)
                if i == 1 { b.eulerAngles.z = 0.10 }
                box(p, x, 0.38 + Double(shelf) * 0.72, -0.351, w * 0.6, 0.023, 0.009, cream, 0.002)
                x += w + 0.04
            }
            if shelf != 1 { box(p, 0.58, 0.41 + Double(shelf) * 0.72, -0.05, 0.43, 0.29, 0.48, shelf == 0 ? cream : pink, 0.055) }
        }
    case "cat-tree":
        cylinder(p, 0, 0.105, 0, 0.88, 0.21, cream)
        torus(p, 0, 0.10, 0, 0.86, 0.045, cream)
        ropePost(p, -0.29, 0.20, 0.21, 1.32, 0.17)
        ropePost(p, 0.51, 0.32, 0.21, 1.32, 0.12)
        cylinder(p, -0.07, 1.59, 0.16, 0.78, 0.18, sage)
        torus(p, -0.07, 1.61, 0.16, 0.75, 0.06, sage)
        ropePost(p, 0.22, 0.32, 1.69, 1.72, 0.17)
        cylinder(p, 0.22, 3.49, 0.32, 0.64, 0.18, sage)
        torus(p, 0.22, 3.59, 0.32, 0.54, 0.16, sage)
        sphere(p, 0.22, 3.63, 0.32, 0.40, sage, SCNVector3(1, 0.32, 1))
        box(p, 0.39, 0.46, -0.38, 0.68, 0.50, 0.64, woodLight, 0.09)
        let door = SCNPlane(width: 0.29, height: 0.32); door.cornerRadius = 0.14; door.materials = [material(0x77573B)]
        let dn = SCNNode(geometry: door); dn.position = SCNVector3(0.39, 0.43, 0.705); p.addChildNode(dn)
        rod(p, SCNVector3(-0.66, 1.57, 0.0), SCNVector3(-0.66, 1.09, 0.0), 0.018, rope)
        sphere(p, -0.66, 0.96, 0, 0.14, cream)
    case "cat-bed":
        cylinder(p, 0, 0.12, 0, 0.91, 0.24, sage)
        torus(p, 0, 0.30, 0, 0.74, 0.20, sage)
        sphere(p, 0, 0.26, 0, 0.72, cream, SCNVector3(1, 0.25, 1))
        for x in [-0.48, 0.48] {
            let g = SCNCone(topRadius: 0.025, bottomRadius: 0.18, height: 0.31); g.materials = [sage]
            let n = SCNNode(geometry: g); n.position = SCNVector3(x, 0.47, -0.59); p.addChildNode(n)
        }
    case "floor-cushion":
        sphere(p, 0, 0.14, 0, 0.93, pink, SCNVector3(1, 0.15, 1))
        torus(p, 0, 0.14, 0, 0.88, 0.024, material(0xD49AAA, "cloth"))
        cylinder(p, 0, 0.279, 0, 0.045, 0.018, cream)
    case "flower-stool":
        feet(p, 0.25, 0.25, 0.69, 0.058)
        cylinder(p, 0, 0.74, 0, 0.31, 0.18, cream)
        for i in 0..<7 { let a = Double(i) * .pi * 2 / 7
            sphere(p, cos(a) * 0.27, 0.79, sin(a) * 0.27, 0.22, cream, SCNVector3(1, 0.6, 1))
        }
        sphere(p, 0, 0.88, 0, 0.20, material(0xE7C568, "cloth"), SCNVector3(1, 0.34, 1))
    case "plant":
        let pot = SCNCone(topRadius: 0.34, bottomRadius: 0.25, height: 0.48); pot.materials = [terra]
        let pn = SCNNode(geometry: pot); pn.position.y = 0.24; p.addChildNode(pn)
        torus(p, 0, 0.47, 0, 0.315, 0.042, terra)
        cylinder(p, 0, 0.46, 0, 0.28, 0.025, material(0x69543B))
        rod(p, SCNVector3(0, 0.46, 0), SCNVector3(0, 1.76, 0), 0.025, woodDark)
        for i in 0..<12 {
            let a = Double(i) * 2.399, y = 0.77 + Double(i) * 0.087
            let x = cos(a) * 0.26, z = sin(a) * 0.26
            rod(p, SCNVector3(0, y - 0.12, 0), SCNVector3(x, y, z), 0.013, green)
            let leaf = sphere(p, x, y + 0.06, z, 0.22, material(i % 2 == 0 ? 0x7FA66D : 0x96B47F), SCNVector3(0.48, 1, 0.72))
            leaf.eulerAngles.z = CGFloat(-cos(a) * 0.7); leaf.eulerAngles.x = CGFloat(sin(a) * 0.6)
        }
    case "rattan-chair":
        feet(p, 0.57, 0.57, 0.45)
        cylinder(p, 0, 0.47, 0, 0.77, 0.18, wicker)
        sphere(p, 0, 0.65, -0.035, 0.71, sage, SCNVector3(1, 0.21, 0.96))
        torus(p, 0, 0.62, -0.035, 0.67, 0.028, sage)
        for i in 0...12 {
            let x = -0.66 + Double(i) * 0.11, top = 1.20 + 0.70 * sqrt(max(0, 1 - x * x / (0.71 * 0.71)))
            rod(p, SCNVector3(x, 0.51, 0.57), SCNVector3(x, top, 0.57), 0.025, wicker)
        }
        for j in 0...12 {
            let y = 0.62 + Double(j) * 0.087, w = min(0.65, 0.71 * sqrt(max(0, 1 - pow(max(0, y - 1.20) / 0.70, 2))))
            rod(p, SCNVector3(-w, y, 0.565), SCNVector3(w, y, 0.565), 0.022, woodLight)
        }
        for i in 0..<20 {
            let a = Double(i) / 19 * .pi
            let b = Double(i + 1) / 19 * .pi
            rod(p, SCNVector3(cos(a) * 0.71, 1.20 + sin(a) * 0.70, 0.57), SCNVector3(cos(b) * 0.71, 1.20 + sin(b) * 0.70, 0.57), 0.065, wicker)
        }
        for x in [-0.71, 0.71] {
            rod(p, SCNVector3(x, 0.52, -0.49), SCNVector3(x, 1.01, -0.49), 0.058, wicker)
            rod(p, SCNVector3(x, 1.01, -0.49), SCNVector3(x, 1.23, 0.53), 0.07, wicker)
            for z in stride(from: -0.43, through: 0.49, by: 0.15) {
                rod(p, SCNVector3(x, 0.55, z), SCNVector3(x, 1.01 + (z + 0.49) * 0.216, z), 0.022, wicker)
            }
        }
    case "side-table":
        cylinder(p, 0, 0.075, 0, 0.29, 0.15, wood)
        torus(p, 0, 0.075, 0, 0.26, 0.04, wood)
        cylinder(p, 0, 0.57, 0, 0.085, 0.94, woodDark)
        cylinder(p, 0, 1.10, 0, 0.48, 0.15, woodLight)
        torus(p, 0, 1.10, 0, 0.44, 0.045, woodLight)
    case "bowl-empty", "bowl-full":
        cylinder(p, 0, 0.06, 0, 0.33, 0.12, material(0x99BEB0))
        torus(p, 0, 0.14, 0, 0.27, 0.07, material(0x99BEB0))
        if kind == "bowl-full" {
            cylinder(p, 0, 0.115, 0, 0.24, 0.025, material(0x99734E))
            for i in 0..<13 { let a = Double(i) * 2.399, r = 0.05 + Double(i % 4) * 0.042
                sphere(p, cos(a) * r, 0.135, sin(a) * r, 0.037, material(i % 2 == 0 ? 0xB58A5D : 0x967049), SCNVector3(1, 0.6, 1))
            }
        }
    default:
        let w = kind == "wall-sunrise" ? 1.5 : kind == "wall-town-memory" ? 1.6 : 1.1
        let h = kind == "wall-sunrise" ? 1.1 : 1.2
        box(p, 0, h / 2, 0, w, h, 0.13, woodDark)
        for x in [-w / 2 + 0.065, w / 2 - 0.065] { box(p, x, h / 2, -0.07, 0.13, h, 0.17, woodLight) }
        for y in [0.065, h - 0.065] { box(p, 0, y, -0.07, w, 0.13, 0.17, woodLight) }
        let g = SCNPlane(width: w - 0.22, height: h - 0.22)
        let m = material(0xFFFFFF).copy() as! SCNMaterial; m.diffuse.contents = illustration(kind); g.materials = [m]
        let n = SCNNode(geometry: g); n.position = SCNVector3(0, h / 2, 0.106); p.addChildNode(n)
    }
    return p
}

func sceneFor(_ model: SCNNode, _ yaw: Double) -> (SCNScene, SCNNode) {
    let scene = SCNScene(); scene.background.contents = NSColor.clear
    scene.rootNode.addChildNode(model)
    let a = yaw * .pi / 180, ce = cos(elevation), se = sin(elevation)
    let centerHeight = (Double(groundPixelY) - 512) / Double(pixelsPerUnit) / ce
    let target = SCNVector3(0, centerHeight, 0)
    let camera = SCNNode(); camera.camera = SCNCamera()
    camera.camera!.usesOrthographicProjection = true; camera.camera!.orthographicScale = 3.2
    camera.camera!.zNear = 0.1; camera.camera!.zFar = 80
    camera.camera!.wantsHDR = false
    camera.position = SCNVector3(-sin(a) * ce * 20, centerHeight + se * 20, cos(a) * ce * 20)
    camera.look(at: target); scene.rootNode.addChildNode(camera)
    // One identical screen-upper-left key and broad fill rig; no shadow-receiving ground exists.
    let key = SCNNode(); key.light = SCNLight(); key.light!.type = .omni
    key.light!.intensity = 930; key.light!.color = color(0xFFF1D9); key.light!.castsShadow = false
    key.position = SCNVector3(-cos(a) * 5 - sin(a) * 4, 9, -sin(a) * 5 + cos(a) * 4)
    scene.rootNode.addChildNode(key)
    let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient
    fill.light!.intensity = 390; fill.light!.color = color(0xF2E9D9); scene.rootNode.addChildNode(fill)
    return (scene, camera)
}

let device = MTLCreateSystemDefaultDevice()!
var count = 0
var assets: [[String: Any]] = []
for kind in allKinds where requested == nil || requested == kind || (requested == "walls" && kind.hasPrefix("wall-")) {
    let object = model(kind)
    let isWall = kind.hasPrefix("wall-")
    if let dimensions = floorDimensions[kind] {
        object.scale = SCNVector3(dimensions.width / dimensions.authoredWidth, 1, dimensions.depth / dimensions.authoredDepth)
    }
    if isWall {
        let (lo, hi) = object.boundingBox
        object.position.y = -(lo.y + hi.y) / 2
    }
    let selectedFacings = asymmetric.contains(kind) ? facings : isWall
        ? ["front", "left", "right"].map { ($0, (wallSurfaceYaw[$0]! - wallReferenceCameraYaw) * .pi / 180) }
        : [facings[0]]
    for (view, yaw) in views { for (facing, rotation) in selectedFacings {
        object.removeFromParentNode(); object.eulerAngles.y = CGFloat(rotation)
        let (scene, camera) = sceneFor(object, yaw)
        let renderer = SCNRenderer(device: device, options: nil); renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
        precondition(bitmap.pixelsWide == side && bitmap.pixelsHigh == side && bitmap.hasAlpha)
        let name = "\(assetBase(kind))-\(view)-\(facing).png"
        try png.write(to: output.appendingPathComponent(name), options: .atomic)
        var pixels: [String: Any] = [:], points: [String: Any] = [:]
        for (name, point) in authoredSurfaces(kind) {
            let world = worldPoint(point, object)
            pixels[name] = projectedPixel(world, yaw); points[name] = pointRecord(world)
        }
        let swapped = facing == "left" || facing == "right"
        let footprint: Any
        if let d = floorDimensions[kind] {
            footprint = ["width": swapped ? d.depth : d.width, "depth": swapped ? d.width : d.depth]
        } else if kind.hasPrefix("bowl-") {
            footprint = ["width": 1.0, "depth": 1.0]
        } else { footprint = NSNull() }
        var entry: [String: Any] = [
            "assetName": String(name.dropLast(4)), "sourceAssetName": assetBase(kind), "fileName": name,
            "kind": coreKind(kind), "state": kind.hasPrefix("bowl-") ? String(kind.dropFirst(5)) : "default",
            "view": view, "facing": facing, "yawDegrees": yaw, "modelYawDegrees": rotation * 180 / .pi,
            "canvasSize": ["width": side, "height": side], "alphaBounds": alphaBounds(bitmap),
            "anchorPixel": ["x": 512, "y": 820], "anchorKind": isWall ? "wallMountCenter" : "footprintGroundCenter",
            "actualModelDimensions": actualDimensions(object), "footprintDimensions": footprint,
            "modelScale": pointRecord(object.scale), "surfacePixels": pixels, "surfaceWorldPoints": points
        ]
        if isWall {
            entry["wallSurfaceYawDegrees"] = wallSurfaceYaw[facing]!
            precondition(cos((yaw + rotation * 180 / .pi) * .pi / 180) > 0)
        }
        assets.append(entry)
        count += 1; print(name)
    } }
}
precondition(count > 0)
let manifestURL = output.appendingPathComponent("manifest.json")
if requested != nil, fm.fileExists(atPath: manifestURL.path) {
    let old = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    precondition(old["formatVersion"] as? Int == 1)
    let oldAssets = old["assets"] as! [[String: Any]]
    let replacements = Set(assets.compactMap { $0["assetName"] as? String })
    assets = oldAssets.filter { !replacements.contains($0["assetName"] as! String) } + assets
}
let manifest: [String: Any] = [
    "formatVersion": 1, "generator": "CatLifeOriginalMeshRenderer-build68", "assetCount": assets.count,
    "coordinateSystem": ["world": "x right, y up, z toward back wall", "pixels": "top-left origin; x right, y down", "front": "-z", "left": "-x", "back": "+z", "right": "+x",
        "wallFacingMeaning": "Wall facing is a surface, not floor rotation: front=neutral 0 degrees, left=left wall interior +45 degrees, right=right wall interior -45 degrees, relative to front-camera normal. Positive wall surface yaw points the normal toward screen right. Actual SceneKit modelYawDegrees=wallSurfaceYawDegrees-30."] ,
    "projection": ["type": "orthographic", "canvasSize": ["width": side, "height": side],
        "pixelsPerUnit": 160, "anchorPixel": ["x": 512, "y": 820], "elevationSin": 0.52,
        "elevationDegrees": elevation * 180 / .pi, "yawByView": Dictionary(uniqueKeysWithValues: views), "wallReferenceCameraYawDegrees": wallReferenceCameraYaw,
        "shadowReceiver": false],
    "surfaceSemantics": ["seatCenter": "top centre of the supporting cushion", "entrySurface": "top supporting surface at the named model-local cardinal rim; points receive the same mesh scale and facing as the image", "foodSurfaceCenter": "full: top centre of the continuous food layer; empty: visible bowl interior centre"],
    "assets": assets
]
let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try manifestData.write(to: manifestURL, options: .atomic)
print("Rendered \(count) original mesh PNGs, \(side)×\(side), 160 pixels/unit, ground anchor (512,820).")
