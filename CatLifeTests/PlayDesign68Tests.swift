import XCTest
import CatGameCore
@testable import CatLife

@MainActor
final class PlayDesign68Tests: XCTestCase {
    func testPlayStageAdaptsToTheSpaceAbovePersistentControls() {
        XCTAssertEqual(PlayDesign68Presentation.stageHeight(available: 420, accessibility: false), 220)
        XCTAssertEqual(PlayDesign68Presentation.stageHeight(available: 600, accessibility: false), 320)
        XCTAssertEqual(PlayDesign68Presentation.stageHeight(available: 240, accessibility: true), 140)
        XCTAssertLessThanOrEqual(PlayDesign68Presentation.stageHeight(available: 420, accessibility: false) + 180, 420)
    }

    func testPlayDesignCopyIsRegisteredInAllLanguagesWithMatchingFormatsAndRealDuration() {
        let tables = [GameStrings.playDesign68Chinese, GameStrings.playDesign68Traditional, GameStrings.playDesign68English]
        let registered = [GameStrings.chinese, GameStrings.traditionalChinese, GameStrings.english]
        let keys = Set(tables[0].keys)
        for (index, table) in tables.enumerated() {
            XCTAssertEqual(Set(table.keys), keys)
            for key in keys {
                XCTAssertFalse(table[key]!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertEqual(registered[index][key], table[key])
                XCTAssertEqual(formats(table[key]!), formats(tables[0][key]!))
            }
        }
        XCTAssertEqual(CatHabitCatalog.playDuration, 20, "The 30-second prototype must not alter the live session.")
        XCTAssertEqual(PlayDesign68Presentation.speedSegment(for: .still), 0)
        XCTAssertEqual(PlayDesign68Presentation.speedSegment(for: .moveAndPause), 0)
        XCTAssertEqual(PlayDesign68Presentation.speedSegment(for: .slowMove), 1)
        XCTAssertEqual(PlayDesign68Presentation.speedSegment(for: .tooFast), 3)
    }

    func testResponseRowsDescribeOnlyAcceptedObservationsAndDoNotRevealUntriedPreferences() throws {
        let date = Date()
        for definition in CatHabitCatalog.all {
            var state = GameSnapshot.fresh(now: date)
            state.cats = [CatState(id: definition.id, name: "Companion", now: date)]
            state.activeCatID = definition.id
            XCTAssertTrue(CatHabitEngine.beginPlay(&state, catID: definition.id, now: date).succeeded)
            var session = try XCTUnwrap(state.catPlay.activeSession)
            XCTAssertEqual(session.endsAt.timeIntervalSince(session.openedAt), 20)
            XCTAssertTrue(PlayDesign68Presentation.tutorialAvailable(in: state))
            for rhythm in CatPlayRhythm.allCases {
                XCTAssertEqual(PlayDesign68Presentation.responseKey(for: rhythm, session: session, definition: definition), "play68.notObserved")
            }
            let comparison: CatPlayRhythm = definition.play == .slowMove ? .moveAndPause : .slowMove
            for (index, rhythm) in [comparison, definition.play].enumerated() {
                let outcome = CatHabitEngine.recordPlayInput(&state, catID: session.catID, sessionID: session.id,
                    report: .init(sequence: index + 1, kind: CatPlayInputKind(rawValue: rhythm.rawValue)!, control: .tap,
                                  duration: 2.1, movementDuration: 0), now: date.addingTimeInterval(Double(index + 1) * 2.2))
                XCTAssertTrue(outcome.succeeded)
                session = try XCTUnwrap(state.catPlay.activeSession)
                XCTAssertEqual(PlayDesign68Presentation.responseKey(for: rhythm, session: session, definition: definition),
                               "catHabits.playHint.\(rhythm.rawValue).\(index == 0 ? "compare" : "match")")
                if index == 0 {
                    XCTAssertEqual(PlayDesign68Presentation.responseKey(for: definition.play, session: session, definition: definition),
                                   "play68.notObserved", "The catalog alone must never fill an unobserved result row.")
                }
            }
            XCTAssertTrue(session.completeResponse)
            XCTAssertEqual(session.effects, CatPlayEffects(), "The first tutorial receipt must show actual zero deltas.")
            XCTAssertFalse(PlayDesign68Presentation.tutorialAvailable(in: state))
        }
        XCTAssertFalse(PlayDesign68Presentation.tutorialAvailable(in: nil))
    }

    func testReadOnlySceneFeedbackTracksTheExistingDemonstrationWithoutExtraInputReports() async throws {
        let scene = CatPlayTogetherScene(appearance: .orange)
        scene.reducedMotion = true
        var inputs: [CatPlayInputKind] = []
        scene.onInput = { kind, _, _, _ in inputs.append(kind) }
        defer { scene.stop() }
        XCTAssertEqual(scene.feedbackKind, .still)
        scene.runControl(.moveAndPause)
        scene.update(0)
        XCTAssertEqual(scene.feedbackKind, .slowMove)
        XCTAssertEqual(scene.activeRhythm, .moveAndPause)
        XCTAssertEqual(inputs, [.moveAndPause])
        for _ in 0..<20 { scene.runControl(.slowMove) }
        try await Task.sleep(for: .milliseconds(1150))
        scene.update(1.15)
        XCTAssertEqual(scene.feedbackKind, .moveAndPause)
        XCTAssertEqual(inputs, [.moveAndPause], "The speed indicator must not generate new reports or toy charges.")
        XCTAssertEqual(scene.pounces, 0, "A display classification cannot grant a pounce or clue.")
    }

    func testControllerKeepsFailedPlayOnScreenAndRetryPublishesOnlyOnePaidReceipt() async throws {
        let date = Date().addingTimeInterval(-10)
        var seed = GameSnapshot.fresh(now: date)
        seed.settings.audio = AudioSettings(musicEnabled: false, effectsEnabled: false, catEnabled: false, haptics: false)
        XCTAssertTrue(CatHabitEngine.beginPlay(&seed, catID: seed.activeCatID, now: date).succeeded)
        let tutorial = try XCTUnwrap(seed.catPlay.activeSession)
        for (index, kind) in [CatPlayInputKind.slowMove, .moveAndPause].enumerated() {
            XCTAssertTrue(CatHabitEngine.recordPlayInput(&seed, catID: tutorial.catID, sessionID: tutorial.id,
                report: .init(sequence: index + 1, kind: kind, control: .tap, duration: 2, movementDuration: 0),
                now: date.addingTimeInterval(Double(index + 1) * 2)).succeeded)
        }
        XCTAssertTrue(CatHabitEngine.endPlay(&seed, catID: tutorial.catID, sessionID: tutorial.id, now: date.addingTimeInterval(5)).succeeded)
        seed.inventory.toys = 3
        let suite = "CatLife-PlayDesign68-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let repository = PlayDesign68Repository(seed)
        let store = GameStore(repository: repository, reminderDefaults: defaults)
        await store.load(); store.enterHome(); store.setForeground(true)
        try await eventually { !store.isBusy }
        let opened = await store.openPlayTogether()
        XCTAssertTrue(opened)
        let session = try XCTUnwrap(store.snapshot?.catPlay.activeSession)
        let controller = CatPlayTogetherController(store: store, session: session)
        defer { controller.finish(); store.setForeground(false) }
        XCTAssertLessThanOrEqual(controller.remaining, 20)
        let before = try XCTUnwrap(store.snapshot)
        await repository.setFailing(true)
        controller.control(.slowMove)
        try await eventually { controller.failed && !controller.working }
        XCTAssertNil(controller.result)
        XCTAssertEqual(store.snapshot, before)
        XCTAssertTrue(store.isShowingPlayTogether, "A failed input must not silently close the activity or show success.")
        await repository.setFailing(false)
        controller.retry(); store.retrySaving()
        try await eventually { !store.isBusy && store.snapshot?.catPlay.activeSession?.paidAt != nil }
        XCTAssertEqual(store.snapshot?.inventory.toys, 2)
        XCTAssertEqual(controller.current.effects.toysSpent, 1)
        controller.finish()
        try await eventually { !store.isBusy && controller.result != nil }
        XCTAssertEqual(controller.result?.session.effects.toysSpent, 1)
        XCTAssertEqual(controller.result?.session.effects, store.snapshot?.catPlay.lastResult?.session.effects)
        XCTAssertEqual(store.snapshot?.inventory.toys, 2)
    }

    private func formats(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%[@df]")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
    }
    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The play transaction did not settle.")
        throw CocoaError(.coderInvalidValue)
    }
}

private actor PlayDesign68Repository: GameSaveRepository {
    let lastLoadDisposition = SaveLoadDisposition.loaded
    private var saved: GameSnapshot
    private var failing = false
    init(_ saved: GameSnapshot) { self.saved = saved }
    func setFailing(_ value: Bool) { failing = value }
    func loadOrCreate(now: Date) -> GameSnapshot { saved }
    func checkWritable() throws { if failing { throw CocoaError(.fileWriteUnknown) } }
    func save(_ value: GameSnapshot) throws { try checkWritable(); saved = value }
}
