import XCTest
import SpriteKit
import CatGameCore
@testable import CatLife

final class RoomArrangementOverlayTests: XCTestCase {
    func testQuickActionsStayInsideScreenAndAboveExpandedTray() {
        for canvas in [CGSize(width: 320, height: 568), CGSize(width: 402, height: 820)] {
            for x: CGFloat in [-80, canvas.width / 2, canvas.width + 80] {
                for y: CGFloat in [0, 240, canvas.height + 50] {
                    let center = RoomArrangementOverlayLayout.center(
                        for: CGRect(x: x, y: y, width: 100, height: 130), canvas: canvas,
                        bottomInset: 250, width: 232)
                    XCTAssertGreaterThanOrEqual(center.x - 116, 12)
                    XCTAssertLessThanOrEqual(center.x + 116, canvas.width - 12)
                    XCTAssertGreaterThanOrEqual(center.y, 180)
                    XCTAssertLessThanOrEqual(center.y + 27, canvas.height - 250)
                }
            }
        }
    }

    func testQuickActionsTrackSelectedFurnitureWhenNoClampingIsNeeded() {
        let center = RoomArrangementOverlayLayout.center(
            for: CGRect(x: 150, y: 300, width: 100, height: 140),
            canvas: CGSize(width: 402, height: 820), bottomInset: 250, width: 232)
        XCTAssertEqual(center, CGPoint(x: 200, y: 268))
    }

    @MainActor
    func testRealDirectionTextureReusesRenderedNodeAndReducedMotionCancelsTheTurnFade() throws {
        let size = CGSize(width: 390, height: 650)
        let transform = RoomArtworkTransform(sceneSize: size, artworkSize: CGSize(width: 1024, height: 1536))
        var item = try XCTUnwrap(FurnitureCatalog.defaultItems.first { $0.kind == .cabinet })
        let placement = FurniturePlacement(itemID: item.id, position: .init(x: 0.7, y: 0.65))
        let source = SKSpriteNode(color: .brown, size: .init(width: 90, height: 100))
        source.position = transform.point(placement.position)
        let renderer = RoomPresentationRenderer()
        let cat = CatActor(), residents = RoomResidentCats(), bowl = SKSpriteNode(), front = SKSpriteNode()
        func update(reducedMotion: Bool) {
            let world = RoomFurnitureWorld(transform: transform, catWidth: 38, bowlSize: .init(width: 30, height: 25),
                bowlPosition: transform.point(.init(x: 0.8, y: 0.8)), items: [item], placements: [placement])
            renderer.configure(world: size, viewport: size, floor: world.roomFloor.polygon, angle: .front, level: 1)
            renderer.update(cat: cat, residents: residents, furniture: [item.id: source], items: [item],
                bowl: bowl, bowlFront: front, restFront: SKSpriteNode(), selection: SKShapeNode(), toy: SKSpriteNode(),
                feeding: false, rest: nil, world: world, reducedMotion: reducedMotion)
        }
        update(reducedMotion: false)
        let node = try XCTUnwrap(renderer.root.childNode(withName: "//furniture-" + item.id) as? SKSpriteNode)
        let originalAnchor = try XCTUnwrap(renderer.anchor("furniture-" + item.id))
        let frontTexture = node.texture
        item.orientation = .left
        update(reducedMotion: false)
        XCTAssertTrue(renderer.root.childNode(withName: "//furniture-" + item.id) === node)
        let left = try XCTUnwrap(FurnitureArtwork68.variant(for: item, placement: placement))
        XCTAssertTrue(node.texture === left.texture)
        XCTAssertFalse(node.texture === frontTexture)
        XCTAssertEqual(node.xScale, 1)
        let action = try XCTUnwrap(node.action(forKey: "turn68"))
        XCTAssertEqual(action.duration, 0.2, accuracy: 0.0001)
        update(reducedMotion: false)
        XCTAssertTrue(node.action(forKey: "turn68") === action, "Refreshing the same direction must not restart the turn.")
        item.orientation = .back
        update(reducedMotion: true)
        let back = try XCTUnwrap(FurnitureArtwork68.variant(for: item, placement: placement))
        XCTAssertTrue(node.texture === back.texture)
        XCTAssertNil(node.action(forKey: "turn68"))
        XCTAssertEqual(node.alpha, source.alpha)
        XCTAssertEqual(node.xScale, 1)
        XCTAssertEqual(renderer.anchor("furniture-" + item.id), originalAnchor)
    }
}
