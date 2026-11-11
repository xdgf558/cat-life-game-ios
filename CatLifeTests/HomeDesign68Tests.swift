import XCTest
import SpriteKit
import CatGameCore
@testable import CatLife

final class HomeDesign68Tests: XCTestCase {
    func testAutomaticPlayInvitationYieldsToAnExplicitGuideOrNewSavedMemory() {
        XCTAssertTrue(HomePromptPriority68.showsAutomaticIntro(eligible: true, hasPinnedMemory: false, hasPendingMemory: false))
        XCTAssertFalse(HomePromptPriority68.showsAutomaticIntro(eligible: true, hasPinnedMemory: true, hasPendingMemory: false),
                       "Choosing a guide must show that choice instead of resurrecting an unseen automatic invitation.")
        XCTAssertFalse(HomePromptPriority68.showsAutomaticIntro(eligible: true, hasPinnedMemory: false, hasPendingMemory: true),
                       "An automatic invitation must not indefinitely block a newly committed memory notice.")
        XCTAssertFalse(HomePromptPriority68.showsAutomaticIntro(eligible: false, hasPinnedMemory: false, hasPendingMemory: false),
                       "Dismissed or completed introductions must remain hidden.")
    }

    func testRestClockOnlyFormatsTheCommittedDeadlineAndClampsItsDisplay() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let rest = CatRest(id: "display", furnitureID: "catBed", startedAt: start,
                           endsAt: start.addingTimeInterval(12), energyReward: 24)
        XCTAssertEqual(HomeRestClock68(rest: rest, at: start.addingTimeInterval(-1)).remaining, 12)
        XCTAssertEqual(HomeRestClock68(rest: rest, at: start.addingTimeInterval(-1)).progress, 0)
        XCTAssertEqual(HomeRestClock68(rest: rest, at: start.addingTimeInterval(6)).remaining, 6)
        XCTAssertEqual(HomeRestClock68(rest: rest, at: start.addingTimeInterval(6)).progress, 0.5)
        XCTAssertEqual(HomeRestClock68(rest: rest, at: start.addingTimeInterval(30)).remaining, 0)
        XCTAssertEqual(HomeRestClock68(rest: rest, at: start.addingTimeInterval(30)).progress, 1)
        XCTAssertEqual(rest.energyGranted, 0, "Rendering must never award recovery.")
        XCTAssertNil(rest.observation, "A resting pose cannot invent a player observation.")
    }

    func testRestAndPinnedCardsStayAboveTheCameraControlsAtSmallAndLargeSizes() {
        for size in [CGSize(width: 355, height: 375), CGSize(width: 382, height: 560)] {
            let bounds = RoomStageLayout.usableRect(in: size)
            let controls = RoomStageLayout.controlsFrame(in: size)
            for height in [CGFloat(44), 150, 600] {
                for frame in [HomeRestLayout68.top(in: bounds, height: height),
                              HomeRestLayout68.bottom(in: bounds, height: height),
                              HomeRestLayout68.request(near: CGRect(x: 10, y: 20, width: 40, height: 30), in: bounds, height: height)] {
                    XCTAssertTrue(bounds.contains(frame))
                    XCTAssertFalse(frame.intersects(controls))
                }
            }
        }
    }

    func testRestStatusLeavesCanvasTouchAreaAndOnlyInterceptsTouchesWhenItsTextOverflows() {
        for size in [CGSize(width: 160, height: 40), CGSize(width: 355, height: 250),
                     CGSize(width: 355, height: 375), CGSize(width: 382, height: 560)] {
            let bounds = CGRect(origin: .init(x: 8, y: 12), size: size)
            for contentHeight in [CGFloat(1), 44, 145, 600, 2_000] {
                let status = HomeRestLayout68.status(in: bounds, height: contentHeight)
                XCTAssertTrue(bounds.contains(status))
                XCTAssertLessThanOrEqual(status.height, bounds.height * 0.55 + 0.001)
                XCTAssertGreaterThanOrEqual(status.minY - bounds.minY, bounds.height * 0.45 - 0.001,
                    "The room must retain a real touch region, including on a tiny stage.")
                XCTAssertEqual(HomeRestLayout68.statusNeedsScrolling(in: bounds, height: contentHeight),
                               contentHeight > bounds.height * 0.55,
                    "Fitting, read-only cards pass through touches; overflowing text scrolls with an explicit wake action.")
            }
        }
    }

    @MainActor
    func testVoiceOverAndFurnitureRequestsNeedConfirmationAndBusyConfirmationDoesNotQueueARest() {
        let scene = RoomScene(size: .init(width: 355, height: 375))
        defer { scene.setPresentationActive(false) }
        var requested: [String] = []
        scene.onRestRequest68 = { requested.append($0) }
        scene.restInFurniture(kind: .catBed)
        scene.requestFurnitureRest68("floorCushion")
        scene.requestFurnitureRest68("cabinet")
        XCTAssertEqual(requested, ["catBed", "floorCushion"])
        XCTAssertNil(scene.activeRest)
        XCTAssertNil(scene.pendingRestID)
        XCTAssertFalse(scene.restPresentation68.canStart, "The initial room planner is not an idle room.")
        scene.confirmFurnitureRest68("catBed")
        XCTAssertNil(scene.activeRest)
        XCTAssertNil(scene.pendingRestID, "A disabled confirmation must not secretly queue a future rest.")
    }

    @MainActor
    func testVoiceOverCatActivationWakesARestingCatInsteadOfOpeningItsProfile() {
        var wakes = 0
        var inspections = 0
        HomeRoomAccessibility68.activate(isResting: true, wake: { wakes += 1 }, inspect: { inspections += 1 })
        XCTAssertEqual(wakes, 1)
        XCTAssertEqual(inspections, 0, "Rest activation must leave the furniture, not open a modal or ask for another rest.")
        HomeRoomAccessibility68.activate(isResting: false, wake: { wakes += 1 }, inspect: { inspections += 1 })
        XCTAssertEqual(wakes, 1)
        XCTAssertEqual(inspections, 1)
    }

    @MainActor
    func testHomeDesignCopyHasTheSameKeysAndFormatArgumentsInAllLanguages() {
        let values = [GameStrings.homeDesign68Chinese, GameStrings.homeDesign68Traditional, GameStrings.homeDesign68English]
        for dictionary in values {
            XCTAssertEqual(Set(dictionary.keys), Set(values[0].keys))
            for (key, text) in dictionary {
                XCTAssertFalse(text.isEmpty)
                let pattern = "%[@df]|%0[0-9]+d"
                let regex = try! NSRegularExpression(pattern: pattern)
                func formats(_ text: String) -> [String] {
                    regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                        .map { String(text[Range($0.range, in: text)!]) }
                }
                XCTAssertEqual(formats(text), formats(values[0][key]!))
            }
            for style in CatBehaviorStyle.allCases { XCTAssertNotNil(dictionary["home68.introduction.\(style.rawValue)"]) }
        }
    }
}
