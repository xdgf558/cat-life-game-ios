import XCTest
@testable import CatGameCore

final class DiarySaveRepositoryTests: XCTestCase {
    func testSaveLoadBackupRecoveryAndLegacyFileIsolation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Place a legacy v0.21 file to guarantee the new repository never modifies it.
        let legacyURL = dir.appendingPathComponent("cat-life-native-v1.json")
        let legacyBytes = Data("{\"legacy\":true}".utf8)
        try legacyBytes.write(to: legacyURL)

        let repo = DiarySaveRepository(directory: dir)
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        var state = try await repo.loadOrCreate(now: t0)
        let d0 = await repo.lastLoadDisposition
        XCTAssertEqual(d0, .created)

        state.coins = 250
        try await repo.save(state, now: t0.addingTimeInterval(600))
        // Second save creates backup of 250-coin state after backupInterval
        state.coins = 400
        try await repo.save(state, now: t0.addingTimeInterval(1200))

        // Corrupt primary save -> must auto-recover backup cleanly.
        try Data("{corrupt".utf8).write(to: repo.saveURL)
        let recovered = try await repo.loadOrCreate(now: t0.addingTimeInterval(1300))
        let d1 = await repo.lastLoadDisposition
        XCTAssertEqual(d1, .recoveredBackup)
        XCTAssertEqual(recovered.coins, 250)

        // Legacy file untouched byte-for-byte.
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
    }

    func testNewerSchemaVersionIsRejectedWithoutOverwriting() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let repo = DiarySaveRepository(directory: dir)
        try Data("{\"schemaVersion\":99}".utf8).write(to: repo.saveURL)
        do {
            _ = try await repo.loadOrCreate()
            XCTFail("Expected unsupportedSchemaVersion")
        } catch let error as SaveRepositoryError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(99))
        }
    }

    func testNonGregorianCalendarsProduceValidGregorianDayKeyAndRespectLocalTimezone() async throws {
        // 2026-11-26 16:30:00 UTC -> 2026-11-26 in UTC, 2026-11-27 00:30 in UTC+8.
        var utcComps = DateComponents()
        utcComps.calendar = Calendar(identifier: .gregorian)
        utcComps.timeZone = TimeZone(secondsFromGMT: 0)
        utcComps.year = 2026
        utcComps.month = 11
        utcComps.day = 26
        utcComps.hour = 16
        utcComps.minute = 30
        let sampleDate = try XCTUnwrap(utcComps.date)

        let tzUTC = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let tzPlus8 = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))

        for identifier in [Calendar.Identifier.republicOfChina, .japanese, .persian] {
            var utcCal = Calendar(identifier: identifier)
            utcCal.timeZone = tzUTC

            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let repo = DiarySaveRepository(directory: dir)

            let created = try await repo.loadOrCreate(now: sampleDate, calendar: utcCal)
            XCTAssertEqual(created.dayKey, 20261126, "Calendar \(identifier) in UTC should produce Gregorian 20261126")
            XCTAssertTrue(created.isValid)

            var plus8Cal = Calendar(identifier: identifier)
            plus8Cal.timeZone = tzPlus8
            XCTAssertEqual(
                DayClock.dayKey(for: DayClock.epochMs(sampleDate), calendar: plus8Cal),
                20261127,
                "Calendar \(identifier) in UTC+8 must roll over at local midnight"
            )
            XCTAssertEqual(DayClock.hour(for: DayClock.epochMs(sampleDate), calendar: plus8Cal), 0)
        }
    }

    func testOutOfRangeFiniteMoodAndSatietyFailValidationAndRecoverBackup() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let repo = DiarySaveRepository(directory: dir)
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        var state = try await repo.loadOrCreate(now: t0)
        state.coins = 123
        try await repo.save(state, now: t0.addingTimeInterval(600))
        state.coins = 200
        try await repo.save(state, now: t0.addingTimeInterval(1200))

        // Out-of-range finite values must be rejected by isValid & save()
        var hugeMood = state
        hugeMood.primaryCat.mood = 1e300
        XCTAssertFalse(hugeMood.isValid)

        var negativeMood = state
        negativeMood.primaryCat.mood = -1
        XCTAssertFalse(negativeMood.isValid)

        var overSatiety = state
        overSatiety.primaryCat.satiety = 101
        XCTAssertFalse(overSatiety.isValid)

        do {
            try await repo.save(hugeMood, now: t0.addingTimeInterval(1300))
            XCTFail("Expected invalidSnapshot when saving out-of-range mood")
        } catch let error as SaveRepositoryError {
            XCTAssertEqual(error, .invalidSnapshot)
        }

        // Write corrupt snapshot directly to primary file -> load must recover backup.
        let corruptBytes = try JSONEncoder().encode(hugeMood)
        try corruptBytes.write(to: repo.saveURL)

        let recovered = try await repo.loadOrCreate(now: t0.addingTimeInterval(1400))
        let disposition = await repo.lastLoadDisposition
        XCTAssertEqual(disposition, .recoveredBackup)
        XCTAssertEqual(recovered.coins, 123)
    }

    func testCorruptTimestampsTriggerBackupRecoveryAndAvoidOverflow() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let repo = DiarySaveRepository(directory: dir)
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        var state = try await repo.loadOrCreate(now: t0)
        state.coins = 310
        try await repo.save(state, now: t0.addingTimeInterval(600))
        state.coins = 500
        try await repo.save(state, now: t0.addingTimeInterval(1200))

        var catMinUpdated = state
        catMinUpdated.primaryCat.updatedAt = .min
        XCTAssertFalse(catMinUpdated.isValid)

        var catMinPet = state
        catMinPet.primaryCat.lastPetAt = .min
        XCTAssertFalse(catMinPet.isValid)

        var energyMinUpdated = state
        energyMinUpdated.energy.updatedAt = .min
        XCTAssertFalse(energyMinUpdated.isValid)

        var visitMin = state
        visitMin.home.lastVisitAt = .min
        XCTAssertFalse(visitMin.isValid)

        var offerMax = state
        offerMax.ads.lastOfferAt = .max
        XCTAssertFalse(offerMax.isValid)

        var negativeCreated = state
        negativeCreated.createdAt = -1
        XCTAssertFalse(negativeCreated.isValid)

        // Write corrupt primary save with cat.updatedAt == Int64.min -> must recover backup cleanly.
        try JSONEncoder().encode(catMinUpdated).write(to: repo.saveURL)
        let launchDate = t0.addingTimeInterval(1500)
        let recovered = try await repo.loadOrCreate(now: launchDate)
        let disposition = await repo.lastLoadDisposition
        XCTAssertEqual(disposition, .recoveredBackup)
        XCTAssertEqual(recovered.coins, 310)

        // Defense-in-depth: settlement helpers must not trap even if fed extreme timestamps in memory.
        let nowMs = DayClock.epochMs(launchDate)
        XCTAssertEqual(DayClock.elapsedMs(from: .min, to: nowMs), .max)
        DiaryHome.settleCats(&catMinUpdated, now: nowMs)
        XCTAssertEqual(catMinUpdated.primaryCat.satiety, 0, accuracy: 0.01)
        energyMinUpdated.energy.current = 0
        XCTAssertEqual(DiaryEnergy.settle(&energyMinUpdated, now: nowMs), DiaryBalance.default.energy.max)
    }
}
