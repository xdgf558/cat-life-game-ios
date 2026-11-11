import Foundation
import XCTest
import CatGameCore
@testable import CatLife

final class RoomArrangementGeometry68Tests: XCTestCase {
    func testOneGridRoundTripsAndUsesHalfOrTenthCellWithoutClampingTheDraft() {
        let world = makeWorld()
        let grid = RoomArrangementGrid68(transform: world.transform)
        let point = grid.worldPoint(grid: CGPoint(x: 0.26, y: -0.14))
        let half = grid.gridPoint(world: grid.snapped(point, enabled: true))
        let free = grid.gridPoint(world: grid.snapped(point, enabled: false))
        XCTAssertEqual(half.x, 0.5, accuracy: 0.000_001); XCTAssertEqual(half.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(free.x, 0.3, accuracy: 0.000_001); XCTAssertEqual(free.y, -0.1, accuracy: 0.000_001)
        let outside = grid.worldPoint(grid: CGPoint(x: -50, y: -50))
        XCTAssertLessThan(grid.normalized(world: outside).x, 0)
        let restored = grid.worldPoint(grid: grid.gridPoint(world: point))
        XCTAssertEqual(restored.x, point.x, accuracy: 0.000_001)
        XCTAssertEqual(restored.y, point.y, accuracy: 0.000_001)
    }

    func testNudgesStayInScreenDirectionsAcrossFrontSectorsAndAllViews() throws {
        let world = makeWorld()
        let grid = RoomArrangementGrid68(transform: world.transform)
        let front = try XCTUnwrap(RoomFrontFloorProjection(polygon: world.roomFloor.polygon,
            destination: CGRect(x: 0, y: 0, width: 500, height: 300)))
        for angle in RoomViewAngle.allCases {
            let projection = RoomViewProjection(worldSize: world.transform.sceneSize, angle: angle, frontFloor: front)
            for normalized in [NormalizedPoint(x: 0.42, y: 0.65), .init(x: 0.55, y: 0.72)] {
                let point = world.transform.point(normalized)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let result = grid.nudged(point, dx: dx, dy: dy, step: 0.5, projection: projection, wall: false)
                    let a = projection.project(point), b = projection.project(result)
                    if dx == 0 { XCTAssertEqual(a.x, b.x, accuracy: 0.000_01); XCTAssertGreaterThan((b.y - a.y) * CGFloat(-dy), 0) }
                    else { XCTAssertEqual(a.y, b.y, accuracy: 0.000_01); XCTAssertGreaterThan((b.x - a.x) * CGFloat(dx), 0) }
                    let ga = grid.gridPoint(world: point), gb = grid.gridPoint(world: result)
                    XCTAssertEqual(hypot(gb.x - ga.x, gb.y - ga.y), 0.5, accuracy: 0.000_01)
                }
            }
        }
    }

    func testInvalidExactPreviewStaysInvalidWhileAnExplicitRotationCanFindSpace() throws {
        let world = makeWorld()
        let grid = RoomArrangementGrid68(transform: world.transform)
        let occupied = try XCTUnwrap(world.center("plant"))
        let start = CGPoint(x: world.transform.sceneSize.width * 0.43, y: world.transform.sceneSize.height * 0.18)
        let exact = RoomArrangementPlanning68.resolve(id: "cabinet", at: occupied, world: world, cat: start,
            grid: grid, snap: false, findNearest: false, snapPoint: false)
        XCTAssertEqual(exact.point, occupied)
        XCTAssertEqual(exact.issue, .overlap("plant"))
        let turned = world.replacingOrientation("cabinet", with: .left)
        let resolved = RoomArrangementPlanning68.resolve(id: "cabinet", at: occupied, world: turned, cat: start,
            grid: grid, snap: true, findNearest: true)
        XCTAssertNil(resolved.issue)
        XCTAssertNotEqual(resolved.point, occupied)
        XCTAssertNil(RoomArrangementPlanning68.issue(id: "cabinet", at: resolved.point, world: resolved.world))
        XCTAssertEqual(resolved.world.item("cabinet")?.orientation, .left)
    }

    func testFurnitureCoveringTheCatUsesASafeOldFloorWalkAndANewFloorEndpoint() throws {
        let world = makeWorld()
        let start = CGPoint(x: world.transform.sceneSize.width * 0.43, y: world.transform.sceneSize.height * 0.18)
        let result = RoomArrangementPlanning68.resolve(id: "cabinet", at: start, world: world, cat: start,
            grid: .init(transform: world.transform), snap: false, findNearest: false, snapPoint: false)
        XCTAssertNil(result.issue)
        XCTAssertGreaterThan(result.catRoute.count, 1)
        let original = world.roomFloor.navigator(bowlAt: world.bowlPosition, precomputeGrid: false)
        XCTAssertTrue(zip(result.catRoute, result.catRoute.dropFirst()).allSatisfy {
            original.segmentIsWalkable(from: $0.0, to: $0.1)
        })
        XCTAssertTrue(result.world.roomFloor.navigator(bowlAt: result.world.bowlPosition, precomputeGrid: false)
            .isWalkable(try XCTUnwrap(result.catRoute.last)))
    }

    func testBothWallsShareAContinuousReversibleCornerAndRetainTheOldRightSeam() throws {
        let world = makeWorld()
        let front = try XCTUnwrap(RoomFrontFloorProjection(polygon: world.roomFloor.polygon,
            destination: CGRect(x: 0, y: 0, width: 500, height: 300)))
        let scale = world.transform.scale
        let back = world.transform.point(.init(x: 442.0 / 1024, y: 530.0 / 1536))
        for angle in RoomViewAngle.allCases {
            let projection = RoomViewProjection(worldSize: world.transform.sceneSize, angle: angle, frontFloor: front)
            for sourceX in [102.4, 280, 441.999, 442, 442.001, 700, 921.6] {
                let x = world.transform.point(.init(x: sourceX / 1024, y: 0.5)).x
                let ground = projection.wallGround(at: x)
                let expectedY = sourceX < 442 ? back.y + (x - back.x) * 255 / 442 : back.y - (x - back.x) * 295 / 582
                XCTAssertEqual(ground.y, expectedY, accuracy: 0.000_001)
                let point = CGPoint(x: x, y: ground.y + 192 * scale)
                let restored = projection.unprojectWallPoint(projection.wallPoint(point))
                XCTAssertEqual(restored.x, point.x, accuracy: 0.000_001)
                XCTAssertEqual(restored.y, point.y, accuracy: 0.000_001)
                XCTAssertNil(RoomArrangementPlanning68.issue(id: "wall", at: point, world: world))
            }
        }
    }

    private func makeWorld() -> RoomFurnitureWorld {
        let viewport = CGSize(width: 375, height: 569), size = CGSize(width: 562.5, height: 853.5)
        return .init(transform: .init(sceneSize: size, artworkSize: CGSize(width: 1024, height: 1536), viewportSize: viewport),
            catWidth: 52.5, bowlSize: CGSize(width: 58.5, height: 48.5),
            bowlPosition: CGPoint(x: size.width * 0.76, y: size.height * 0.21),
            items: [.init(id: "cabinet", kind: .cabinet), .init(id: "plant", kind: .plant), .init(id: "wall", kind: .wallCat)],
            placements: [.init(itemID: "plant", position: .init(x: 0.6, y: 0.65))])
    }
}
