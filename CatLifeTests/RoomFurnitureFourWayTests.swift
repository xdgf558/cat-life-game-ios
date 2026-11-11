import Foundation
import XCTest
import CatGameCore
@testable import CatLife

final class RoomFurnitureFourWayTests: XCTestCase {
    @MainActor
    func testSchema14FurnitureAndActiveRestReachTheAppWithoutRewritingFloorOrPosition() async throws {
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        var expected = GameSnapshot.fresh(now: now)
        expected.home = HomeState(roomLevel: 6)
        expected.home.furniture[0].floor = .upper
        expected.home.furniture[0].position = .init(x: 0.42, y: 0.67)
        expected.inventory.furniture[0].orientation = .left
        expected.player.gold = 876
        expected.inventory.food = 17
        expected.cats[0].energy = 20
        XCTAssertTrue(GameEngine.startCatRest(&expected, catID: expected.activeCatID,
            furnitureID: "catBed", sessionID: "v14-app-rest", now: now).succeeded)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppFurnitureSchema14-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = FileSaveRepository(directory: directory)
        let legacy = try legacySnapshotFixture(expected, schema: 14)
        try legacy.write(to: repository.saveURL)
        let loaded = try await repository.loadOrCreate(now: now)
        XCTAssertEqual(loaded, expected)
        XCTAssertEqual(loaded.schemaVersion, 15)
        XCTAssertEqual(try Data(contentsOf: repository.saveURL), legacy)
        let world = makeWorld(items: loaded.inventory.furniture, placements: loaded.home.placements(on: .upper))
        let cabinet = try XCTUnwrap(world.item("cabinet"))
        XCTAssertEqual(cabinet.orientation, .left)
        let size = FurnitureCatalog.footprint(for: cabinet).artworkSize
        XCTAssertEqual(world.footprint(cabinet), CGSize(width: size.width * world.transform.visualScale,
                                                      height: size.height * world.transform.visualScale))
        XCTAssertEqual(world.placements, expected.home.placements(on: .upper))
    }

    func testTurningAndMovingAnUpperFloorInstanceRetainsItsPlacementAndOtherItems() throws {
        let items = [FurnitureItem(id: "cabinet", kind: .cabinet), .init(id: "wall", kind: .wallCat)]
        let placements = [FurniturePlacement(itemID: "cabinet", position: .init(x: 0.5, y: 0.7), floor: .upper)]
        let world = makeWorld(items: items, placements: placements)
        let center = try XCTUnwrap(world.center("cabinet"))
        for orientation in FurnitureOrientation.allCases {
            let turned = world.replacingOrientation("cabinet", with: orientation)
            XCTAssertEqual(turned.item("cabinet")?.orientation, orientation)
            XCTAssertEqual(turned.item("wall"), world.item("wall"))
            XCTAssertEqual(turned.placements, placements)
            let rectangle = turned.rectangle(try XCTUnwrap(turned.item("cabinet")), at: center)
            XCTAssertEqual(turned.floorObstacles(), [rectangle])
            let moved = turned.replacing("cabinet", with: CGPoint(x: center.x + 10, y: center.y - 5))
            XCTAssertEqual(moved.placements.first?.floor, .upper)
            XCTAssertEqual(moved.item("cabinet")?.orientation, orientation)
        }
        XCTAssertEqual(world.items, items)
        XCTAssertEqual(world.placements, placements)
        for orientation in [FurnitureOrientation.left, .back, .right] {
            XCTAssertEqual(world.replacingOrientation("wall", with: orientation).items, items)
        }
        XCTAssertEqual(world.replacingOrientation("unknown", with: .left).items, items)
    }

    func testGridAxesRotateBeforeProjectionAndFourTurnsRestoreEveryOffset() throws {
        let world = makeWorld(items: [], placements: [])
        let offset = CGPoint(x: 24, y: 16)
        let expected: [FurnitureOrientation: CGPoint] = [
            .front: offset, .left: CGPoint(x: 32, y: -12),
            .back: CGPoint(x: -24, y: -16), .right: CGPoint(x: -32, y: 12)
        ]
        for direction in FurnitureOrientation.allCases {
            let rotated = world.rotatedFloorOffset(offset, by: direction)
            let expectedPoint = try XCTUnwrap(expected[direction])
            XCTAssertEqual(rotated.x, expectedPoint.x, accuracy: 0.000_001)
            XCTAssertEqual(rotated.y, expectedPoint.y, accuracy: 0.000_001)
        }
        var rotated = offset
        for _ in 0..<4 { rotated = world.rotatedFloorOffset(rotated, by: .left) }
        XCTAssertEqual(rotated.x, offset.x, accuracy: 0.000_001)
        XCTAssertEqual(rotated.y, offset.y, accuracy: 0.000_001)
    }

    func testEveryRestDirectionUsesItsOwnEntranceAndAnExactSafeReverseExit() throws {
        for viewport in [CGSize(width: 375, height: 436), CGSize(width: 402, height: 776)] {
            for kind in [FurnitureKind.catBed, .floorCushion] {
                let item = FurnitureItem(id: "rest", kind: kind)
                let original = makeWorld(viewport: viewport, items: [item],
                    placements: [.init(itemID: item.id, position: .init(x: 0.5, y: 0.7), floor: .upper)])
                let start = CGPoint(x: original.transform.sceneSize.width * 0.43,
                                    y: original.transform.sceneSize.height * 0.18)
                let front = try XCTUnwrap(original.restVisit(to: item.id, from: start))
                let center = try XCTUnwrap(original.center(item.id))
                for direction in FurnitureOrientation.allCases {
                    let world = original.replacingOrientation(item.id, with: direction)
                    let context = "\(viewport), \(kind), \(direction)"
                    let visit = try XCTUnwrap(world.restVisit(to: item.id, from: start), context)
                    XCTAssertEqual(visit.entryOrientation, direction, "An open layout must prefer the furniture's own facing.")
                    XCTAssertEqual(visit.elevation, front.elevation, accuracy: 0.000_001,
                                   "Physical height must stay vertical when the floor facing changes.")
                    let expected = world.rotatedFloorPoint(front.plan.restPoint, around: center, by: direction)
                    XCTAssertEqual(visit.plan.restPoint.x, expected.x, accuracy: 0.000_001, context)
                    XCTAssertEqual(visit.plan.restPoint.y, expected.y, accuracy: 0.000_001, context)
                    XCTAssertEqual(visit.plan.exit, Array(visit.plan.entry.reversed()), context)
                    XCTAssertTrue(visit.target.contains(visit.plan.restPoint), context)
                    let dx = visit.plan.restPoint.x - visit.plan.stage.x
                    if abs(dx) > 0.000_001 { XCTAssertEqual(visit.plan.facing, dx > 0 ? 1 : -1, context) }
                    switch direction {
                    case .front: XCTAssertLessThan(visit.plan.stage.y, visit.target.minY, context)
                    case .left: XCTAssertLessThan(visit.plan.stage.x, visit.target.minX, context)
                    case .back: XCTAssertGreaterThan(visit.plan.stage.y, visit.target.maxY, context)
                    case .right: XCTAssertGreaterThan(visit.plan.stage.x, visit.target.maxX, context)
                    }
                    for route in [visit.plan.entry, visit.plan.exit] {
                        XCTAssertTrue(zip(route, route.dropFirst()).allSatisfy {
                            visit.navigation.segmentIsWalkable(from: $0.0, to: $0.1)
                        }, context)
                    }
                    let approach = world.roomFloor.navigator(bowlAt: world.bowlPosition, precomputeGrid: false)
                    XCTAssertTrue(zip(visit.plan.approach, visit.plan.approach.dropFirst()).allSatisfy {
                        approach.segmentIsWalkable(from: $0.0, to: $0.1)
                    }, context)
                    let barrier = CGRect(x: visit.plan.restPoint.x - 1, y: visit.plan.restPoint.y - 1, width: 2, height: 2)
                    XCTAssertNil(world.restVisit(to: item.id, from: start, additionalObstacles: [barrier]),
                                 "A blocked sleeping footprint cannot gain an unsafe fallback: \(context)")
                }
            }
        }
    }

    func testLegacyMirroredBedBesideTheLeftWallUsesAValidatedAlternateRimWithoutMoving() throws {
        let now = Date(timeIntervalSince1970: 1_794_500_000)
        var expected = GameSnapshot.fresh(now: now)
        let bed = try XCTUnwrap(expected.inventory.furniture.firstIndex { $0.id == "catBed" })
        expected.inventory.furniture[bed].orientation = .left
        expected.cats[0].energy = 20
        XCTAssertTrue(GameEngine.startCatRest(&expected, catID: expected.activeCatID,
            furnitureID: "catBed", sessionID: "mirrored-wall-rest", now: now).succeeded)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(GameSnapshot.self, from: legacySnapshotFixture(expected, schema: 14))
        XCTAssertEqual(loaded, expected)
        let world = makeWorld(viewport: CGSize(width: 375, height: 569), scale: 1,
            items: loaded.inventory.furniture, placements: loaded.home.furniture)
        let start = CGPoint(x: world.transform.sceneSize.width * 0.43, y: world.transform.sceneSize.height * 0.18)
        let visit = try XCTUnwrap(world.restVisit(to: "catBed", from: start))
        XCTAssertEqual(visit.item.orientation, .left)
        XCTAssertEqual(visit.entryOrientation, .front, "The left rim is against the wall; the next safe rim is the front.")
        XCTAssertEqual(world.placements, expected.home.furniture)
        XCTAssertEqual(visit.plan.exit, Array(visit.plan.entry.reversed()))
        for path in [visit.plan.entry, visit.plan.exit] {
            XCTAssertTrue(zip(path, path.dropFirst()).allSatisfy {
                visit.navigation.segmentIsWalkable(from: $0.0, to: $0.1)
            })
        }
        let approach = world.roomFloor.navigator(bowlAt: world.bowlPosition, precomputeGrid: false)
        XCTAssertTrue(zip(visit.plan.approach, visit.plan.approach.dropFirst()).allSatisfy {
            approach.segmentIsWalkable(from: $0.0, to: $0.1)
        })
        let dx = visit.plan.restPoint.x - visit.plan.stage.x
        XCTAssertGreaterThan(abs(dx), 0.000_001)
        XCTAssertEqual(visit.plan.facing, dx > 0 ? 1 : -1)
    }

    private func makeWorld(viewport: CGSize = CGSize(width: 375, height: 436),
                           scale: CGFloat = 1.5,
                           items: [FurnitureItem], placements: [FurniturePlacement]) -> RoomFurnitureWorld {
        let size = CGSize(width: viewport.width * scale, height: viewport.height * scale)
        let bowlWidth = min(viewport.width * 0.156, viewport.height * 0.185)
        return .init(transform: .init(sceneSize: size, artworkSize: CGSize(width: 1024, height: 1536), viewportSize: viewport),
            catWidth: min(viewport.width * 0.14, viewport.height * 0.172),
            bowlSize: CGSize(width: bowlWidth, height: bowlWidth * 0.83),
            bowlPosition: CGPoint(x: size.width * 0.76, y: size.height * 0.21),
            items: items, placements: placements)
    }

    /// Write the released vocabulary at the fixture boundary, never in the decoder.
    private func legacySnapshotFixture(_ snapshot: GameSnapshot, schema: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
        object["schemaVersion"] = schema
        var inventory = try XCTUnwrap(object["inventory"] as? [String: Any])
        var items = try XCTUnwrap(inventory["furniture"] as? [[String: Any]])
        for index in items.indices {
            switch items[index]["orientation"] as? String {
            case "front": items[index]["orientation"] = "normal"
            case "left": items[index]["orientation"] = "mirrored"
            default:
                XCTFail("This legacy fixture cannot contain a newer direction.")
                throw SaveRepositoryError.invalidSnapshot
            }
        }
        inventory["furniture"] = items
        object["inventory"] = inventory
        return try JSONSerialization.data(withJSONObject: object)
    }
}
