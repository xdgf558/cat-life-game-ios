import XCTest
import UIKit
import CatGameCore
@testable import CatLife

final class FurnitureArtwork68Tests: XCTestCase {
    @MainActor
    func testEveryRoomAndFacingSelectsAnExistingCroppedAsset() throws {
        XCTAssertEqual(FurnitureArtwork68.records.count, 105)
        var selected = Set<String>()
        for kind in FurnitureKind.allCases {
            for angle in RoomViewAngle.allCases {
                for orientation in FurnitureOrientation.allCases {
                    let item = FurnitureItem(id: "fixture", kind: kind, orientation: orientation)
                    let placements: [FurniturePlacement?] = kind.supportsRotation ? [nil] : [nil,
                        .init(itemID: item.id, position: .init(x: 0.3, y: 0.4)),
                        .init(itemID: item.id, position: .init(x: 0.7, y: 0.4))]
                    for placement in placements {
                        let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: item, angle: angle, placement: placement))
                        selected.insert(variant.assetName)
                        XCTAssertEqual(FurnitureArtwork68.assetName(for: item, angle: angle, placement: placement), variant.assetName)
                        let image = try XCTUnwrap(UIImage(named: variant.assetName)?.cgImage)
                        XCTAssertEqual(image.width, Int(variant.croppedSize.width))
                        XCTAssertEqual(image.height, Int(variant.croppedSize.height))
                        XCTAssertLessThan(max(image.width, image.height), 1024)
                    }
                }
            }
        }
        for hasFood in [false, true] {
            for angle in RoomViewAngle.allCases {
                selected.insert(try XCTUnwrap(FurnitureArtwork68.bowlVariant(hasFood: hasFood, angle: angle)).assetName)
            }
        }
        XCTAssertEqual(selected, Set(FurnitureArtwork68.records.keys))
    }

    @MainActor
    func testRotatedFurnitureKeepsOnePixelScaleAndRebasesTheFloorAnchor() throws {
        let front = try XCTUnwrap(FurnitureArtwork68.variant(for: .init(id: "cabinet", kind: .cabinet)))
        for angle in RoomViewAngle.allCases {
            for orientation in FurnitureOrientation.allCases {
                let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: .init(id: "cabinet", kind: .cabinet, orientation: orientation), angle: angle))
                XCTAssertEqual(variant.referenceFrontAlphaWidth, front.croppedSize.width)
                let size = variant.size(referenceWidth: 244)
                XCTAssertEqual(size.width / variant.croppedSize.width, 244 / front.croppedSize.width, accuracy: 0.000_001)
                XCTAssertEqual(size.height / variant.croppedSize.height, 244 / front.croppedSize.width, accuracy: 0.000_001)
                XCTAssertEqual(variant.anchorPoint.x * variant.croppedSize.width + variant.record.alphaBounds.x, 512, accuracy: 0.000_001)
                XCTAssertEqual((1 - variant.anchorPoint.y) * variant.croppedSize.height + variant.record.alphaBounds.y, 820, accuracy: 0.000_001)
            }
        }
    }

    @MainActor
    func testRoundFurnitureAndWallSurfacesIgnoreFloorRotation() throws {
        for kind in [FurnitureKind.catBed, .floorCushion, .flowerStool, .plant, .sideTable] {
            for orientation in FurnitureOrientation.allCases {
                let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: .init(id: "round", kind: kind, orientation: orientation)))
                XCTAssertEqual(variant.record.facing, "front")
            }
        }
        let wall = FurnitureItem(id: "wall", kind: .wallCat, orientation: .back)
        XCTAssertEqual(FurnitureArtwork68.variant(for: wall)?.record.facing, "front")
        for (x, surface) in [(0.469999, "left"), (0.47, "right"), (0.7, "right")] {
            let placement = FurniturePlacement(itemID: wall.id, position: .init(x: x, y: 0.4))
            let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: wall, placement: placement))
            XCTAssertEqual(variant.record.facing, surface)
            XCTAssertEqual(variant.record.anchorKind, "wallMountCenter")
            XCTAssertGreaterThan(cos((variant.record.yawDegrees + (variant.record.modelYawDegrees ?? 0)) * .pi / 180), 0.45)
        }
    }

    @MainActor
    func testMeshContactOffsetsAndBowlStateRegistration() throws {
        for angle in RoomViewAngle.allCases {
            for kind in [FurnitureKind.catBed, .floorCushion] {
                let variant = try XCTUnwrap(FurnitureArtwork68.variant(for: .init(id: "rest", kind: kind), angle: angle))
                for name in ["seatCenter", "frontEntrySurface", "leftEntrySurface", "backEntrySurface", "rightEntrySurface"] {
                    let pixel = try XCTUnwrap(variant.record.surfacePixels[name])
                    let offset = try XCTUnwrap(variant.surfaceOffset(name, referenceWidth: variant.referenceFrontAlphaWidth))
                    XCTAssertEqual(offset.x, pixel.x - 512, accuracy: 0.000_001)
                    XCTAssertEqual(offset.y, 820 - pixel.y, accuracy: 0.000_001)
                }
                XCTAssertNil(variant.surfaceOffset("missing", referenceWidth: 344))
            }
            let empty = try XCTUnwrap(FurnitureArtwork68.bowlVariant(hasFood: false, angle: angle))
            let full = try XCTUnwrap(FurnitureArtwork68.bowlVariant(hasFood: true, angle: angle))
            XCTAssertNotEqual(empty.assetName, full.assetName)
            XCTAssertEqual(empty.croppedSize, full.croppedSize)
            XCTAssertEqual(empty.anchorPoint, full.anchorPoint)
            XCTAssertEqual(empty.referenceFrontAlphaWidth, full.referenceFrontAlphaWidth)
            XCTAssertGreaterThan(try XCTUnwrap(full.surfaceOffset("foodSurfaceCenter", referenceWidth: 100)).y, 0)
        }
        let sample = try XCTUnwrap(FurnitureArtwork68.bowlVariant(hasFood: true))
        XCTAssertTrue(sample.texture === sample.texture)
        XCTAssertEqual(sample.size(referenceWidth: 0), .zero)
        XCTAssertNil(sample.surfaceOffset("foodSurfaceCenter", referenceWidth: .infinity))
    }
}
