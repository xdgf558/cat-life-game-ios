import SpriteKit
import XCTest
import CatGameCore
@testable import CatLife

final class RoomArrangementRendering68Tests: XCTestCase {
    @MainActor
    func testClippedGridNeverDrawsAcrossAConcaveWindowBay() {
        let polygon: [CGPoint] = [.init(x: 0,y: 0), .init(x: 8,y: 0), .init(x: 8,y: 8),
                                  .init(x: 5,y: 8), .init(x: 5,y: 3), .init(x: 3,y: 3),
                                  .init(x: 3,y: 8), .init(x: 0,y: 8)]
        let segments = RoomArrangementRendering68.clipped(.init(x: -1,y: 5), .init(x: 9,y: 5), polygon: polygon)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].0.x, 0, accuracy: 0.001)
        XCTAssertEqual(segments[0].1.x, 3, accuracy: 0.001)
        XCTAssertEqual(segments[1].0.x, 5, accuracy: 0.001)
        XCTAssertEqual(segments[1].1.x, 8, accuracy: 0.001)
    }

    @MainActor
    func testDraggingFootprintFollowsThePreviewWithoutRewritingSavedPlacement() throws {
        let transform = RoomArtworkTransform(sceneSize: .init(width: 402, height: 600), artworkSize: .init(width: 1024, height: 1536))
        let item = FurnitureItem(id: "cabinet", kind: .cabinet)
        let placement = FurniturePlacement(itemID: item.id, position: .init(x: 0.6, y: 0.6))
        let world = RoomFurnitureWorld(transform: transform, catWidth: 40, bowlSize: .init(width: 30, height: 25),
            bowlPosition: .zero, items: [item], placements: [placement])
        let artwork = RoomArrangementRendering68()
        let original = try XCTUnwrap(world.center(item.id))
        let preview = CGPoint(x: original.x - 120, y: original.y - 70)
        let projection = RoomViewProjection(worldSize: transform.sceneSize, angle: .right)
        artwork.update(world: world, projection: projection, editing: true, selectedID: item.id, bowlSelected: false,
                       issues: [item.id: .outside], previewCenter: preview)
        let shape = try XCTUnwrap(artwork.childNode(withName: "arrangement-footprint68") as? SKShapeNode)
        XCTAssertTrue(try XCTUnwrap(shape.path).contains(projection.project(preview)))
        XCTAssertFalse(try XCTUnwrap(shape.path).contains(projection.project(original)))
        XCTAssertEqual(world.placements, [placement])
    }

    @MainActor
    func testRenderedFurnitureChangesModelFaceWithoutMirroringOrMovingSavedAnchors() throws {
        let worldSize = CGSize(width: 402, height: 600)
        let transform = RoomArtworkTransform(sceneSize: worldSize, artworkSize: .init(width: 1024, height: 1536))
        let cat = CatActor(), residents = RoomResidentCats(), bowl = SKSpriteNode(), front = SKSpriteNode()
        let renderer = RoomPresentationRenderer()
        let node = SKSpriteNode(color: .brown, size: .init(width: 90, height: 70))
        node.position = transform.point(.init(x: 0.7, y: 0.65))
        let original = node.position
        let placement = FurniturePlacement(itemID: "cabinet", position: .init(x: 0.7, y: 0.65))
        var renderedNames = Set<String>()
        for angle in RoomViewAngle.allCases {
            for orientation in FurnitureOrientation.allCases {
                let item = FurnitureItem(id: "cabinet", kind: .cabinet, orientation: orientation)
                let world = RoomFurnitureWorld(transform: transform, catWidth: 38, bowlSize: .init(width: 30, height: 25),
                    bowlPosition: transform.point(.init(x: 0.8, y: 0.8)), items: [item], placements: [placement])
                renderer.configure(world: worldSize, viewport: worldSize, floor: world.roomFloor.polygon, angle: angle, level: 1)
                renderer.update(cat: cat, residents: residents, furniture: [item.id: node], items: [item],
                    bowl: bowl, bowlFront: front, restFront: SKSpriteNode(), selection: SKShapeNode(), toy: SKSpriteNode(),
                    feeding: false, rest: nil, world: world, reducedMotion: true)
                let sprite = try XCTUnwrap(renderer.root.childNode(withName: "//furniture-cabinet") as? SKSpriteNode)
                let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: item, angle: angle, placement: placement))
                renderedNames.insert(variant.assetName)
                XCTAssertTrue(sprite.texture === variant.texture)
                XCTAssertEqual(sprite.xScale, 1)
                XCTAssertEqual(sprite.anchorPoint.x, variant.anchorPoint.x, accuracy: 0.000_001)
                XCTAssertEqual(sprite.anchorPoint.y, variant.anchorPoint.y, accuracy: 0.000_001)
                XCTAssertEqual(node.position, original)
                XCTAssertNotNil(renderer.frame("furniture-cabinet"))
                let screen = try XCTUnwrap(renderer.anchor("furniture-cabinet"))
                let point = renderer.worldPoint(screen: screen)
                XCTAssertEqual(point.x, original.x, accuracy: 0.001)
                XCTAssertEqual(point.y, original.y, accuracy: 0.001)
            }
        }
        XCTAssertEqual(renderedNames.count, 12)
    }
}
