import SpriteKit
import UIKit
import XCTest
import CatGameCore
@testable import CatLife

final class RoomRenderedRestTests: XCTestCase {
#if DEBUG
    @MainActor
    func testRenderedPawOffsetsSurviveAllViewsDuringRealBedAndCushionEntryAndExit() async throws {
        var captured = Set<String>()
        for kind in [FurnitureKind.catBed, .floorCushion] {
            for orientation in FurnitureOrientation.allCases {
                let scene = RoomScene(size: CGSize(width: 375, height: 569))
                scene.scaleMode = .aspectFit
                var snapshot = GameSnapshot.fresh()
                snapshot.home.roomLevel = 3
                let item = FurnitureItem(id: kind.rawValue, kind: kind, orientation: orientation)
                snapshot.inventory.furniture = [item]
                snapshot.home.furniture = [.init(itemID: item.id, position: .init(x: 0.5, y: 0.7))]
                scene.apply(snapshot: snapshot, editing: false)
                let playback = try RenderedRestPlayback(scene: scene)
                defer { playback.close() }
                let deadline = Date().addingTimeInterval(20)
                while scene.presentationPhase != "idle", Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
                XCTAssertEqual(scene.presentationPhase, "idle")
                XCTAssertEqual(scene.size, CGSize(width: 375, height: 569))
                let cat = try XCTUnwrap(scene.childNode(withName: "cat") as? CatActor)
                cat.speed = 3
                let target = try XCTUnwrap(scene.furnitureNodes[item.id])
                XCTAssertNotNil(scene.furnitureWorld.restVisit(to: item.id, from: cat.position))
                let completedRests = cat.completedRests, completedExits = scene.diagnostics.restExits
                var begins = 0, ends = 0
                var sessionID: String?
                scene.onRestingFurnitureChanged = { furnitureID, currentSessionID, catID in
                    XCTAssertEqual(catID, snapshot.activeCatID)
                    if let furnitureID {
                        XCTAssertEqual(furnitureID, item.id)
                        begins += 1; sessionID = currentSessionID
                    } else {
                        XCTAssertEqual(currentSessionID, sessionID)
                        ends += 1
                    }
                }
                scene.onRestRequest68 = { [weak scene] id in scene?.confirmFurnitureRest68(id) }
                scene.restInFurniture(kind: kind)
                var entryViews = Set<RoomViewAngle>(), exitViews = Set<RoomViewAngle>(), seatedViews = Set<RoomViewAngle>()
                var requestedExit = false, finished = false
                while Date() < deadline {
                    if let rest = scene.activeRest, let step = cat.artworkLandmarks68.step {
                        let entry = cat.restPhase == .entering && (step.frame == 2 || step.frame == 3)
                            && cat.stepProgress >= rest.entryContactProgress - 0.000_1
                        let exit = cat.restPhase == .leaving && step.frame == 5 && cat.stepProgress >= 0.8799
                        if entry || exit {
                            let sourcePosition = cat.position, targetPosition = target.position
                            let originalWarp = cat.renderSprite68.warpGeometry
                            let originalSize = cat.renderSprite68.size
                            for angle in RoomViewAngle.allCases {
                                try turn(scene, to: angle)
                                scene.updateRoomPresentation()
                                XCTAssertEqual(cat.position, sourcePosition, "A view changes presentation, never the current path point.")
                                XCTAssertEqual(target.position, targetPosition)
                                XCTAssertTrue(cat.renderSprite68.warpGeometry === originalWarp)
                                XCTAssertEqual(cat.renderSprite68.size, originalSize)
                                let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: item, angle: angle))
                                let root = scene.roomPresentation.root
                                let furniture = try XCTUnwrap(try presentationNode("furniture-" + item.id, scene: scene, source: target) as? SKSpriteNode)
                                let clone = try catClone(scene, source: cat)
                                if entry {
                                    let paw = warpedPoint(step.frontUV, sprite: clone, in: root)
                                    let rim = try XCTUnwrap(variant.surfaceOffset(rest.entryOrientation.rawValue + "EntrySurface", referenceWidth: target.size.width))
                                    let support = furniture.convert(rim, to: root)
                                    XCTAssertEqual(paw.x, support.x, accuracy: 0.8, "\(kind)/\(orientation)/\(angle): actual forepaw must reach the mesh rim.")
                                    XCTAssertEqual(paw.y, support.y, accuracy: 0.8)
                                    try assertAuditMatchesClone(paw, logical: cat.frontPawContact, cat: cat, scene: scene)
                                    entryViews.insert(angle)
                                    let captureAngle: RoomViewAngle? = orientation == .front ? .front : orientation == .left ? .left : orientation == .right ? .right : nil
                                    let name = "mesh-\(kind.rawValue)-\(angle)-\(orientation.rawValue)-frontPaws"
                                    if captureAngle == angle, captured.insert(name).inserted {
                                        add(try playback.snapshot(named: name))
                                    }
                                }
                                if exit {
                                    let paw = warpedPoint(step.rearUV, sprite: clone, in: root)
                                    let seat = try XCTUnwrap(variant.surfaceOffset("seatCenter", referenceWidth: target.size.width))
                                    let support = furniture.convert(seat, to: root)
                                    XCTAssertEqual(paw.y, support.y, accuracy: 0.8, "The rear paw remains on the seat while the forepaw steps down.")
                                    XCTAssertLessThan(abs(paw.x - support.x), furniture.size.width * 0.45 / scene.roomPresentation.camera.scale)
                                    try assertAuditMatchesClone(paw, logical: cat.rearPawContact, cat: cat, scene: scene)
                                    exitViews.insert(angle)
                                }
                                assertUpperBodyUnchanged(clone: clone, source: cat.renderSprite68)
                            }
                        }
                    }
                    if cat.restPhase == .resting, !requestedExit {
                        for angle in RoomViewAngle.allCases {
                            try turn(scene, to: angle)
                            scene.updateRoomPresentation()
                            let root = scene.roomPresentation.root
                            let furniture = try XCTUnwrap(try presentationNode("furniture-" + item.id, scene: scene, source: target) as? SKSpriteNode)
                            let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: item, angle: angle))
                            let seat = try XCTUnwrap(variant.surfaceOffset("seatCenter", referenceWidth: target.size.width))
                            let expected = furniture.convert(seat, to: root)
                            let pose = try XCTUnwrap(try catClone(scene, source: cat).parent).convert(CGPoint.zero, to: root)
                            XCTAssertEqual(pose.x, expected.x, accuracy: 0.8)
                            XCTAssertEqual(pose.y, expected.y, accuracy: 0.8)
                            seatedViews.insert(angle)
                            let name = "mesh-\(kind.rawValue)-front-front-lying"
                            if orientation == .front, angle == .front, captured.insert(name).inserted {
                                add(try playback.snapshot(named: name))
                            }
                        }
                        XCTAssertEqual(cat.completedRests, completedRests + 1)
                        requestedExit = true
                        scene.leaveFurnitureRest()
                    }
                    if requestedExit, scene.activeRest == nil, !cat.isPerforming, scene.presentationPhase == "idle" { finished = true; break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertTrue(finished, "\(kind)/\(orientation): complete the real entry, stay and exit.")
                XCTAssertEqual(entryViews, Set(RoomViewAngle.allCases))
                XCTAssertEqual(exitViews, Set(RoomViewAngle.allCases))
                XCTAssertEqual(seatedViews, Set(RoomViewAngle.allCases))
                XCTAssertEqual(cat.completedRests, completedRests + 1)
                XCTAssertEqual(scene.diagnostics.restExits, completedExits + 1)
                XCTAssertEqual(begins, 1); XCTAssertEqual(ends, 1)
            }
        }
    }

    @MainActor
    func testRealRoomMealMouthTouchesTheMeshFoodSurfaceInEveryView() async throws {
        let scene = RoomScene(size: CGSize(width: 375, height: 569))
        scene.scaleMode = .aspectFit
        scene.apply(snapshot: .fresh(), editing: false)
        let playback = try RenderedRestPlayback(scene: scene)
        defer { playback.close() }
        let deadline = Date().addingTimeInterval(20)
        while scene.presentationPhase != "idle", Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let cat = try XCTUnwrap(scene.childNode(withName: "cat") as? CatActor)
        cat.speed = 3
        let completed = cat.completedMeals
        scene.playFeedback(kind: .feed)
        var views = Set<RoomViewAngle>()
        var capturedMeal = false
        while Date() < deadline {
            if let mouth = cat.artworkLandmarks68.mouth {
                for angle in RoomViewAngle.allCases {
                    try turn(scene, to: angle)
                    scene.updateRoomPresentation()
                    let root = scene.roomPresentation.root
                    let actor = try presentationNode("cat", scene: scene, source: cat)
                    let bowl = try XCTUnwrap(try presentationNode("bowl", scene: scene, source: scene.bowl) as? SKSpriteNode)
                    let variant = try XCTUnwrap(FurnitureArtwork68.bowlVariant(hasFood: true, angle: angle))
                    let offset = try XCTUnwrap(variant.surfaceOffset("foodSurfaceCenter", referenceWidth: scene.bowl.size.width))
                    let food = bowl.convert(offset, to: root)
                    let lip = actor.convert(mouth, to: root)
                    let radius = 0.24 * 160 * scene.bowl.size.width / variant.referenceFrontAlphaWidth / scene.roomPresentation.camera.scale
                    let x = (lip.x - food.x) / radius, y = (lip.y - food.y) / (radius * 0.52)
                    XCTAssertLessThanOrEqual(x * x + y * y, 1, "Actual lips must touch food, not the bowl's opaque body.")
                    views.insert(angle)
                    if angle == .front, !capturedMeal {
                        add(try playback.snapshot(named: "mesh-meal-front-mouth-contact"))
                        capturedMeal = true
                    }
                }
            }
            if cat.completedMeals == completed + 1, !cat.isPerforming { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(views, Set(RoomViewAngle.allCases))
        XCTAssertEqual(cat.completedMeals, completed + 1)
        XCTAssertFalse(cat.isPerforming)
        let bowl = try XCTUnwrap(try presentationNode("bowl", scene: scene, source: scene.bowl) as? SKSpriteNode)
        XCTAssertTrue(bowl.texture === FurnitureArtwork68.bowlVariant(hasFood: false, angle: scene.roomViewAngle)?.texture)
    }

    @MainActor
    private func turn(_ scene: RoomScene, to angle: RoomViewAngle) throws {
        for _ in 0..<2 where scene.roomViewAngle != angle { scene.turnRoomView(by: (angle.rawValue - scene.roomViewAngle.rawValue).signum()) }
        guard scene.roomViewAngle == angle else { throw RenderedRestFailure.viewUnavailable }
    }

    @MainActor
    private func presentationNode(_ name: String, scene: RoomScene, source: SKNode) throws -> SKNode {
        let root = scene.roomPresentation.root
        func find(in parent: SKNode) -> SKNode? {
            for child in parent.children {
                if child.name == name { return child }
                if let result = find(in: child) { return result }
            }
            return nil
        }
        let node = try XCTUnwrap(find(in: root), "Missing renderer clone: \(name)")
        XCTAssertFalse(node === source, "Contact evidence must come from the renderer clone, not the simulation.")
        var ancestor = node.parent
        while let current = ancestor, current !== root { ancestor = current.parent }
        XCTAssertTrue(ancestor === root)
        return node
    }

    @MainActor
    private func catClone(_ scene: RoomScene, source: CatActor) throws -> SKSpriteNode {
        let root = try presentationNode("cat", scene: scene, source: source)
        func find(in parent: SKNode) -> SKSpriteNode? {
            for child in parent.children {
                if let sprite = child as? SKSpriteNode, sprite.texture === source.renderSprite68.texture { return sprite }
                if let result = find(in: child) { return result }
            }
            return nil
        }
        let sprite = try XCTUnwrap(find(in: root))
        XCTAssertFalse(sprite === source.renderSprite68)
        return sprite
    }

    @MainActor
    private func warpedPoint(_ uv: CGPoint, sprite: SKSpriteNode, in root: SKNode) -> CGPoint {
        var point = uv
        if let grid = sprite.warpGeometry as? SKWarpGeometryGrid {
            let columns = grid.numberOfColumns, rows = grid.numberOfRows
            let gx = min(CGFloat(columns), max(0, uv.x * CGFloat(columns))), gy = min(CGFloat(rows), max(0, uv.y * CGFloat(rows)))
            let col = min(columns - 1, Int(gx)), row = min(rows - 1, Int(gy))
            let fx = Float(gx - CGFloat(col)), fy = Float(gy - CGFloat(row))
            let low = grid.destPosition(at: row * (columns + 1) + col) * (1 - fx) + grid.destPosition(at: row * (columns + 1) + col + 1) * fx
            let high = grid.destPosition(at: (row + 1) * (columns + 1) + col) * (1 - fx) + grid.destPosition(at: (row + 1) * (columns + 1) + col + 1) * fx
            let dest = low * (1 - fy) + high * fy
            point = CGPoint(x: CGFloat(dest.x), y: CGFloat(dest.y))
        }
        return sprite.convert(CGPoint(x: (point.x - sprite.anchorPoint.x) * sprite.size.width,
                                      y: (point.y - sprite.anchorPoint.y) * sprite.size.height), to: root)
    }

    @MainActor
    private func assertAuditMatchesClone(_ point: CGPoint, logical: CGPoint?, cat: CatActor, scene: RoomScene) throws {
        let reported = try XCTUnwrap(scene.roomPresentation.displayedPoint(try XCTUnwrap(logical), source: cat, key: "cat"))
        XCTAssertEqual(reported.x, point.x + scene.size.width / 2, accuracy: 0.01)
        XCTAssertEqual(reported.y, scene.size.height / 2 - point.y, accuracy: 0.01)
    }

    @MainActor
    private func assertUpperBodyUnchanged(clone: SKSpriteNode, source: SKSpriteNode) {
        XCTAssertEqual(clone.size, source.size)
        XCTAssertEqual(clone.xScale, source.xScale); XCTAssertEqual(clone.yScale, source.yScale)
        guard let grid = clone.warpGeometry as? SKWarpGeometryGrid else { return }
        let base = source.warpGeometry as? SKWarpGeometryGrid
        for row in (grid.numberOfRows * 3 / 4)...grid.numberOfRows {
            for col in 0...grid.numberOfColumns {
                let index = row * (grid.numberOfColumns + 1) + col
                let expected = base?.destPosition(at: index) ?? SIMD2(Float(col) / Float(grid.numberOfColumns), Float(row) / Float(grid.numberOfRows))
                let actual = grid.destPosition(at: index)
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.000_001)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.000_001)
            }
        }
    }
#endif
}

private enum RenderedRestFailure: Error { case viewUnavailable, snapshotUnavailable }

/// Supplies real SpriteKit action frames; aspectFit keeps the canonical test canvas unchanged.
@MainActor
private final class RenderedRestPlayback {
    private let scene: RoomScene
    private let window: UIWindow
    private let view: SKView

    init(scene: RoomScene) throws {
        self.scene = scene
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: windowScene)
        window.frame = windowScene.coordinateSpace.bounds
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        view = SKView(frame: window.bounds)
        view.preferredFramesPerSecond = 60
        let controller = UIViewController()
        controller.view = view
        window.rootViewController = controller
        view.presentScene(scene)
        window.isHidden = false
    }

    func snapshot(named name: String) throws -> XCTAttachment {
        // Capture the actual camera-local renderer subtree inside its viewport,
        // excluding simulation artwork outside the already presented room.
        let bounds = CGRect(x: -scene.size.width / 2, y: -scene.size.height / 2,
                            width: scene.size.width, height: scene.size.height)
        guard let image = view.texture(from: scene.roomPresentation.root, crop: bounds)?.cgImage() else {
            throw RenderedRestFailure.snapshotUnavailable
        }
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    func close() {
        scene.setPresentationActive(false)
        scene.removeAllActions()
        scene.children.forEach { $0.removeAllActions() }
        view.presentScene(nil)
        window.isHidden = true
        window.rootViewController = nil
    }
}
