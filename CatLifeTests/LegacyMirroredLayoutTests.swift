import Foundation
import XCTest
import CatGameCore
@testable import CatLife

/// Fixtures freeze the released collision dimensions independently of today's catalog.
final class LegacyMirroredLayoutTests: XCTestCase {
    private let viewports = [CGSize(width: 375, height: 436), CGSize(width: 402, height: 776)]
    private let configurations: [(Int, HomeFloor)] = [(1, .ground), (8, .ground), (6, .upper), (8, .upper)]
    private let fixtures: [(FurnitureKind, CGSize)] = [
        (.cabinet, .init(width: 186, height: 78)), (.catTree, .init(width: 160, height: 82)),
        (.catBed, .init(width: 292, height: 144)), (.plant, .init(width: 70, height: 42)),
        (.floorCushion, .init(width: 154, height: 80)), (.flowerStool, .init(width: 126, height: 68)),
        (.bookcase, .init(width: 190, height: 76)), (.rattanChair, .init(width: 158, height: 88)),
        (.sideTable, .init(width: 136, height: 72))
    ]

    // The released small plant shares a kind but has a distinct collision multiplier.
    private var mirrorCases: [(FurnitureKind, CGSize, String?)] {
        fixtures.map { ($0.0, $0.1, nil) } + [(.plant, .init(width: 70 * 0.78, height: 42 * 0.78), "plantSmall")]
    }

    func testEveryOldMirroredKindKeepsItsLegalWallEdgeWithoutMovingOrBlockingFeeding() throws {
        for viewport in viewports {
            for (level, floor) in configurations {
                for (kind, dimensions, itemID) in mirrorCases {
                    let empty = world(viewport: viewport, level: level, items: [], placements: [])
                    let scale = empty.transform.visualScale
                    let old = CGSize(width: dimensions.width * scale, height: dimensions.height * scale)
                    let polygon = empty.roomFloor.polygon
                    let minX = try XCTUnwrap(polygon.map(\.x).min()), minY = try XCTUnwrap(polygon.map(\.y).min())
                    let widerWhenTurned = 2 * dimensions.height > dimensions.width
                    let point = CGPoint(x: minX + old.width / 2 + 0.02,
                        y: minY + old.height / 2 + (widerWhenTurned ? 20 : 0.02))
                    let fixture = try legacyWorld(viewport: viewport, level: level, floor: floor,
                        kind: kind, center: point, itemID: itemID)
                    let context = "\(kind)/\(viewport)/L\(level)/\(floor)"
                    XCTAssertNil(RoomArrangementPlanning68.issue(id: fixture.id, at: point, world: fixture.old),
                        "The original wall-edge fixture must be legal: \(context)")
                    XCTAssertNil(RoomArrangementPlanning68.issue(id: fixture.id, at: point, world: fixture.migrated),
                        "An untouched migrated item must not become red at the same wall: \(context)")
                    try assertSameFootprintAndPositions(fixture, expected: old, context: context)
                    try assertFeedingStillWorks(fixture, context: context)
                }
            }
        }
    }

    func testEveryOldMirroredKindKeepsAReleasedSafeGapBesideAnotherFurniture() throws {
        for viewport in viewports {
            for (level, floor) in configurations {
                for (kind, dimensions, itemID) in mirrorCases {
                    let empty = world(viewport: viewport, level: level, items: [], placements: [])
                    let scale = empty.transform.visualScale
                    let point = empty.transform.point(.init(x: 0.5, y: 0.7))
                    let old = CGSize(width: dimensions.width * scale, height: dimensions.height * scale)
                    let neighbor = CGSize(width: 70 * scale, height: 42 * scale)
                    let widerWhenTurned = 2 * dimensions.height > dimensions.width
                    let neighborPoint = widerWhenTurned
                        ? CGPoint(x: point.x + old.width / 2 + neighbor.width / 2 + 2.001, y: point.y)
                        : CGPoint(x: point.x, y: point.y + old.height / 2 + neighbor.height / 2 + 2.001)
                    let fixture = try legacyWorld(viewport: viewport, level: level, floor: floor,
                        kind: kind, center: point, neighbor: neighborPoint, itemID: itemID)
                    let context = "\(kind)/\(viewport)/L\(level)/\(floor)"
                    XCTAssertNil(RoomArrangementPlanning68.issue(id: fixture.id, at: point, world: fixture.old),
                        "The released furniture gap is legal: \(context)")
                    XCTAssertNil(RoomArrangementPlanning68.issue(id: fixture.id, at: point, world: fixture.migrated),
                        "Migration must not make the same untouched pair overlap: \(context)")
                    try assertSameFootprintAndPositions(fixture, expected: old, context: context)
                    try assertFeedingStillWorks(fixture, context: context)
                }
            }
        }
    }

    func testEveryOldMirroredKindLeavesTheSameNarrowCatPassageOpen() throws {
        for viewport in viewports {
            for (kind, dimensions, itemID) in mirrorCases {
                let base = world(viewport: viewport, level: 1, items: [], placements: [])
                let point = base.transform.point(.init(x: 0.5, y: 0.7))
                let fixture = try legacyWorld(viewport: viewport, level: 1, floor: .ground, kind: kind, center: point, itemID: itemID)
                let old = CGSize(width: dimensions.width * base.transform.visualScale,
                                 height: dimensions.height * base.transform.visualScale)
                let migrated = fixture.migrated.footprint(try XCTUnwrap(fixture.migrated.item(fixture.id)))
                let turned = CGSize(width: dimensions.height * 2 * base.transform.visualScale,
                                    height: dimensions.width / 2 * base.transform.visualScale)
                let feet = base.roomFloor.catFootprint
                let horizontalGrowth = turned.width > old.width
                let growth = horizontalGrowth ? turned.width - old.width : turned.height - old.height
                let clearance = growth / 4
                let bounds = horizontalGrowth
                    ? CGRect(x: 0, y: 0, width: old.width + feet.width + clearance,
                             height: old.height + 2 * feet.height + 40)
                    : CGRect(x: 0, y: 0, width: old.width + 2 * feet.width + 40,
                             height: old.height + feet.height + clearance)
                let target = horizontalGrowth
                    ? CGPoint(x: bounds.maxX - old.width / 2, y: bounds.midY)
                    : CGPoint(x: bounds.midX, y: bounds.maxY - old.height / 2)
                let start = horizontalGrowth
                    ? CGPoint(x: feet.width / 2 + clearance / 2, y: feet.height / 2 + 1)
                    : CGPoint(x: feet.width / 2 + 1, y: feet.height / 2 + clearance / 2)
                let end = horizontalGrowth
                    ? CGPoint(x: start.x, y: bounds.maxY - feet.height / 2 - 1)
                    : CGPoint(x: bounds.maxX - feet.width / 2 - 1, y: start.y)
                let polygon = [CGPoint(x: 0, y: 0), CGPoint(x: bounds.maxX, y: 0),
                               CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: 0, y: bounds.maxY)]
                func navigator(_ size: CGSize) -> RoomNavigation {
                    .init(floor: polygon,
                          obstacles: [CGRect(x: target.x - size.width / 2, y: target.y - size.height / 2,
                                             width: size.width, height: size.height)],
                          footprint: feet, cellSize: 7, precomputeGrid: false)
                }
                let context = "\(kind)/\(viewport)"
                XCTAssertNotNil(navigator(old).route(from: start, to: end), "Released passage must be usable: \(context)")
                XCTAssertNil(navigator(turned).route(from: start, to: end),
                    "The fixture must expose the original migration bug, rather than leave a broad alternate route: \(context)")
                XCTAssertNotNil(navigator(migrated).route(from: start, to: end),
                    "A schema-14 mirror must retain its only existing passage: \(context)")
            }
        }
    }

    func testMovingALegacyMirrorUsesNewBoundsForBothPreviewAndPlacement() throws {
        for viewport in viewports {
            for (level, floor) in configurations {
                for (kind, dimensions, itemID) in mirrorCases {
                    let empty = world(viewport: viewport, level: level, items: [], placements: [])
                    let old = CGSize(width: dimensions.width * empty.transform.visualScale,
                                     height: dimensions.height * empty.transform.visualScale)
                    let minX = try XCTUnwrap(empty.roomFloor.polygon.map(\.x).min())
                    let minY = try XCTUnwrap(empty.roomFloor.polygon.map(\.y).min())
                    let horizontalGrowth = 2 * dimensions.height > dimensions.width
                    let nearWall = CGPoint(x: minX + old.width / 2 + 0.02,
                        y: minY + old.height / 2 + (horizontalGrowth ? 20 : 0.02))
                    let sourcePoint = empty.transform.point(.init(x: 0.5, y: 0.7))
                    let fixture = try legacyWorld(viewport: viewport, level: level, floor: floor,
                        kind: kind, center: sourcePoint, itemID: itemID)
                    XCTAssertNil(RoomArrangementPlanning68.issue(id: fixture.id, at: sourcePoint, world: fixture.migrated))
                    XCTAssertNil(RoomArrangementPlanning68.issue(id: fixture.id, at: nearWall, world: fixture.old))
                    XCTAssertEqual(RoomArrangementPlanning68.issue(id: fixture.id, at: nearWall, world: fixture.migrated), .outside)
                    let result = RoomArrangementPlanning68.resolve(id: fixture.id, at: nearWall, world: fixture.migrated,
                        cat: CGPoint(x: empty.transform.sceneSize.width * 0.6, y: empty.transform.sceneSize.height * 0.15),
                        grid: .init(transform: empty.transform), snap: false, findNearest: false, snapPoint: false)
                    XCTAssertEqual(result.issue, .outside)
                    XCTAssertFalse(try XCTUnwrap(result.world.item(fixture.id)).usesLegacyFootprint)
                }
            }
        }
    }

    func testLegacyMirroredBedAndCushionStillHaveAnActualSafeRestAndReverseExit() throws {
        for viewport in viewports {
            for (level, floor) in configurations {
                for kind in [FurnitureKind.catBed, .floorCushion] {
                    let base = world(viewport: viewport, level: level, items: [], placements: [])
                    let fixture = try legacyWorld(viewport: viewport, level: level, floor: floor,
                        kind: kind, center: base.transform.point(.init(x: 0.5, y: 0.7)))
                    let start = CGPoint(x: base.transform.sceneSize.width * 0.6,
                                        y: base.transform.sceneSize.height * 0.15)
                    XCTAssertNotNil(fixture.old.restVisit(to: fixture.id, from: start))
                    let visit = try XCTUnwrap(fixture.migrated.restVisit(to: fixture.id, from: start))
                    XCTAssertEqual(visit.plan.exit, Array(visit.plan.entry.reversed()))
                    for route in [visit.plan.entry, visit.plan.exit] {
                        XCTAssertTrue(zip(route, route.dropFirst()).allSatisfy {
                            visit.navigation.segmentIsWalkable(from: $0.0, to: $0.1)
                        })
                    }
                    XCTAssertEqual(fixture.migrated.placements, fixture.old.placements)
                }
            }
        }
    }

    private struct Fixture {
        let id: String
        let old: RoomFurnitureWorld
        let migrated: RoomFurnitureWorld
    }

    private func legacyWorld(viewport: CGSize, level: Int, floor: HomeFloor, kind: FurnitureKind,
                             center: CGPoint, neighbor: CGPoint? = nil, itemID: String? = nil) throws -> Fixture {
        let base = world(viewport: viewport, level: level, items: [], placements: [])
        let id = itemID ?? "legacy_" + kind.rawValue
        var snapshot = GameSnapshot.fresh(now: Date(timeIntervalSince1970: 1_794_500_000))
        var owned = snapshot.inventory.furniture.filter { $0.id != id }
        owned.append(.init(id: id, kind: kind, orientation: .left))
        var placements = [FurniturePlacement(itemID: id, position: base.transform.normalized(center), floor: floor)]
        if let neighbor {
            owned.append(.init(id: "legacy_neighbor", kind: .plant))
            placements.append(.init(itemID: "legacy_neighbor", position: base.transform.normalized(neighbor), floor: floor))
        }
        snapshot.inventory.furniture = owned
        snapshot.home = HomeState(furniture: placements, roomLevel: level)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
        object["schemaVersion"] = 14
        var inventory = try XCTUnwrap(object["inventory"] as? [String: Any])
        var items = try XCTUnwrap(inventory["furniture"] as? [[String: Any]])
        for index in items.indices {
            let orientation = try XCTUnwrap(items[index]["orientation"] as? String)
            items[index]["orientation"] = orientation == "left" ? "mirrored" : "normal"
            items[index].removeValue(forKey: "usesLegacyFootprint")
        }
        inventory["furniture"] = items; object["inventory"] = inventory
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(GameSnapshot.self, from: data)
        XCTAssertNoThrow(try NativeSaveTransfer.encode(snapshot: migrated, exportedAt: migrated.meta.lastSyncAt),
            "The fixture must represent readable released progress.")
        XCTAssertEqual(migrated.home.furniture, placements, "Migration cannot move a prior layout or change its floor.")
        XCTAssertEqual(migrated.inventory.furniture.first { $0.id == id }?.orientation, .left)
        var originalItems = owned
        for index in originalItems.indices { originalItems[index].orientation = .front }
        return .init(id: id,
            old: world(viewport: viewport, level: level, items: originalItems, placements: placements),
            migrated: world(viewport: viewport, level: level, items: migrated.inventory.furniture,
                            placements: migrated.home.placements(on: floor)))
    }

    private func assertSameFootprintAndPositions(_ fixture: Fixture, expected: CGSize, context: String) throws {
        let item = try XCTUnwrap(fixture.migrated.item(fixture.id))
        let actual = fixture.migrated.footprint(item)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_001, context)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_001, context)
        XCTAssertEqual(fixture.migrated.floorObstacles(), fixture.old.floorObstacles(), context)
        XCTAssertEqual(fixture.migrated.placements, fixture.old.placements, context)
    }

    private func assertFeedingStillWorks(_ fixture: Fixture, context: String) throws {
        let size = fixture.old.transform.sceneSize
        let start = CGPoint(x: size.width * 0.6, y: size.height * 0.15)
        XCTAssertNotNil(fixture.old.roomFloor.feedingPlan(from: start, bowlAt: fixture.old.bowlPosition,
            navigator: fixture.old.roomFloor.navigator(bowlAt: fixture.old.bowlPosition, precomputeGrid: false), firstReachable: true),
            "The original fixture must allow feeding: \(context)")
        XCTAssertNotNil(fixture.migrated.roomFloor.feedingPlan(from: start, bowlAt: fixture.migrated.bowlPosition,
            navigator: fixture.migrated.roomFloor.navigator(bowlAt: fixture.migrated.bowlPosition, precomputeGrid: false), firstReachable: true),
            "Migration must leave the feeding route intact: \(context)")
    }

    private func world(viewport: CGSize, level: Int, items: [FurnitureItem], placements: [FurniturePlacement]) -> RoomFurnitureWorld {
        let scale = CGFloat(HomeCatalog.level(level)?.worldScale ?? 1)
        let size = CGSize(width: viewport.width * scale, height: viewport.height * scale)
        let bowlWidth = min(viewport.width * 0.156, viewport.height * 0.185)
        return .init(transform: .init(sceneSize: size, artworkSize: .init(width: 1024, height: 1536), viewportSize: viewport),
            catWidth: min(viewport.width * 0.14, viewport.height * 0.172),
            bowlSize: .init(width: bowlWidth, height: bowlWidth * 0.83),
            bowlPosition: CGPoint(x: size.width * 0.76, y: size.height * 0.21), items: items, placements: placements)
    }
}
