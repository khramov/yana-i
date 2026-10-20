import CloudKit
import Foundation
import Testing
import YanaDomain
import YanaSync
@testable import YanaMac

@Suite struct CloudKitRecordMappingTests {
    private func outgoing() async throws -> (PortfolioRepository, OutgoingRecord) {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "Long term"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "VTI", currency: .usd), to: p.id).holding
        let out = try #require(try await repo.coordinator.outgoingRecord(for: RecordKey(entity: .holding, id: h.id)))
        return (repo, out)
    }

    @Test func recordCarriesPayloadAndScalarFields() async throws {
        let (_, out) = try await outgoing()
        let record = CloudKitRecordMapping.record(for: out, serverMetadata: nil)
        #expect(record.recordType == "Holding")
        #expect(record.recordID.recordName == out.key.id.uuidString.lowercased())
        #expect(record.recordID.zoneID.zoneName == "Portfolio")
        #expect(record.recordID.zoneID.ownerName == CKCurrentUserDefaultName)
        #expect(record["payload"] as? Data == out.payload)
        #expect(record["schemaVersion"] as? Int64 == 1)
        #expect(record["revision"] as? Int64 == out.version.revision)
        #expect(record["modifiedAt"] as? Date == out.version.modifiedAt)
        #expect(record["deviceID"] as? String == out.version.deviceID.uuidString.lowercased())
        #expect(record["deleted"] as? Int64 == 0)
        #expect(Set(record.allKeys()) == Set(CloudKitRecordMapping.Field.all))
    }

    @Test func tombstoneIsMarkedDeleted() async throws {
        let (repo, out) = try await outgoing()
        try await repo.deleteHolding(out.key.id)
        let deleted = try #require(try await repo.coordinator.outgoingRecord(for: out.key))
        #expect(CloudKitRecordMapping.record(for: deleted, serverMetadata: nil)["deleted"] as? Int64 == 1)
    }

    @Test func payloadRoundTripsAndKeyIsRecovered() async throws {
        let (_, out) = try await outgoing()
        let record = CloudKitRecordMapping.record(for: out, serverMetadata: nil)
        #expect(try CloudKitRecordMapping.key(of: record) == out.key)
        #expect(try CloudKitRecordMapping.payload(of: record) == out.payload)
    }

    @Test func mismatchedOrMissingPayloadIsRejected() async throws {
        let (_, out) = try await outgoing()
        let wrongName = CKRecord(recordType: "Holding", recordID: CloudKitRecordMapping.recordID(UUID()))
        CloudKitRecordMapping.apply(out, to: wrongName)
        #expect(throws: CloudKitMappingError.payloadMismatch) { try CloudKitRecordMapping.payload(of: wrongName) }

        let wrongType = CKRecord(recordType: "Transaction", recordID: CloudKitRecordMapping.recordID(for: out.key))
        CloudKitRecordMapping.apply(out, to: wrongType)
        #expect(throws: CloudKitMappingError.payloadMismatch) { try CloudKitRecordMapping.payload(of: wrongType) }

        let empty = CKRecord(recordType: "Holding", recordID: CloudKitRecordMapping.recordID(for: out.key))
        #expect(throws: CloudKitMappingError.missingPayload) { try CloudKitRecordMapping.payload(of: empty) }

        let unknown = CKRecord(recordType: "Quote", recordID: CloudKitRecordMapping.recordID(for: out.key))
        #expect(throws: CloudKitMappingError.unknownRecordType("Quote")) { try CloudKitRecordMapping.key(of: unknown) }
    }

    @Test func savesBuildOnKnownServerSystemFields() async throws {
        let (_, out) = try await outgoing()
        let server = CloudKitRecordMapping.record(for: out, serverMetadata: nil)
        let metadata = CloudKitRecordMapping.encodeSystemFields(of: server)
        let decoded = try #require(CloudKitRecordMapping.decodeSystemFields(metadata))
        #expect(decoded.recordID == server.recordID && decoded.recordType == server.recordType)
        // System fields only: the payload is not archived with them.
        #expect(decoded["payload"] == nil)

        let next = CloudKitRecordMapping.record(for: out, serverMetadata: metadata)
        #expect(next.recordID == server.recordID && next["payload"] as? Data == out.payload)

        // Metadata for another record is ignored rather than reused.
        let other = CKRecord(recordType: "Holding", recordID: CloudKitRecordMapping.recordID(UUID()))
        let fresh = CloudKitRecordMapping.record(for: out, serverMetadata: CloudKitRecordMapping.encodeSystemFields(of: other))
        #expect(fresh.recordID == CloudKitRecordMapping.recordID(for: out.key))
        #expect(CloudKitRecordMapping.record(for: out, serverMetadata: Data("junk".utf8)).recordID == fresh.recordID)
    }

    @Test func errorsAreClassifiedForStatus() {
        #expect(SyncIssue(CKError(.networkUnavailable)) == .offline)
        #expect(SyncIssue(CKError(.networkFailure)) == .offline)
        #expect(SyncIssue(CKError(.requestRateLimited)) == .offline)
        #expect(SyncIssue(CKError(.serverRecordChanged)) == nil)
        #expect(SyncIssue(CKError(.operationCancelled)) == nil)
        #expect(SyncIssue(CKError(.zoneNotFound)) == nil)
        guard case .failed(let quota) = SyncIssue(CKError(.quotaExceeded)) else { Issue.record("quota"); return }
        #expect(quota.contains("storage is full"))
        #expect(SyncIssue(CKError(.notAuthenticated)) == .failed(reason: SyncAccountStatus.noAccount.reason!))
    }

    @Test func accountStatusMapping() {
        #expect(SyncAccountStatus(CKAccountStatus.available) == .available)
        #expect(SyncAccountStatus(CKAccountStatus.noAccount) == .noAccount)
        #expect(SyncAccountStatus(CKAccountStatus.restricted) == .restricted)
        #expect(SyncAccountStatus(CKAccountStatus.temporarilyUnavailable) == .temporarilyUnavailable)
        #expect(SyncAccountStatus(CKAccountStatus.couldNotDetermine) == .couldNotDetermine)
    }
}

@Suite struct PortfolioStoreSyncBookkeepingTests {
    @Test func keyLookupFindsTheEntity() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "KO", currency: .usd), to: p.id).holding
        #expect(try await repo.store.key(forRecordID: p.id) == RecordKey(entity: .portfolio, id: p.id))
        #expect(try await repo.store.key(forRecordID: h.id) == RecordKey(entity: .holding, id: h.id))
        #expect(try await repo.store.key(forRecordID: UUID()) == nil)
    }

    @Test func serverMetadataIsStoredReplacedAndRemoved() async throws {
        let store = try await makeRepository().store
        let key = RecordKey(entity: .goal, id: UUID())
        #expect(try await store.serverMetadata(for: key) == nil)
        try await store.saveServerMetadata(Data([1]), for: key)
        try await store.saveServerMetadata(Data([2]), for: key)
        #expect(try await store.serverMetadata(for: key) == Data([2]))
        try await store.removeServerMetadata(for: key)
        #expect(try await store.serverMetadata(for: key) == nil)
    }

    @Test func flagAllForUploadQueuesEverythingAndForgetsMetadata() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let h = try await repo.addHolding(HoldingDraft(ticker: "KO", currency: .usd), to: p.id).holding
        let pKey = RecordKey(entity: .portfolio, id: p.id), hKey = RecordKey(entity: .holding, id: h.id)
        for key in [pKey, hKey] {
            try await repo.coordinator.didUpload(key, version: try #require(try await repo.store.record(for: key)).version)
            try await repo.store.saveServerMetadata(Data([9]), for: key)
        }
        #expect(try await repo.store.keysNeedingUpload().isEmpty)

        try await repo.store.flagAllForUpload()
        #expect(Set(try await repo.store.keysNeedingUpload()) == [pKey, hKey])
        #expect(try await repo.store.serverMetadata(for: pKey) == nil)
    }

    @Test func removeAllRecordsClearsMetadataButKeepsDeviceID() async throws {
        let repo = try await makeRepository()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        let key = RecordKey(entity: .portfolio, id: p.id)
        try await repo.store.saveServerMetadata(Data([1]), for: key)
        try await repo.store.saveSyncEngineState(Data([2]))
        let device = try await repo.store.deviceID()

        try await repo.store.removeAllRecords()
        #expect(try await repo.store.portfolios(includingDeleted: true).isEmpty)
        #expect(try await repo.store.serverMetadata(for: key) == nil)
        #expect(try await repo.store.syncEngineState() == nil)
        #expect(try await repo.store.deviceID() == device)
    }
}

/// Records what the controller asks of the backend.
actor FakeSyncBackend: SyncBackend {
    enum Call: Equatable { case start(suspended: Bool), suspend, resume, reset, uploadAll, syncNow }
    private(set) var calls: [Call] = []
    let store: PortfolioStore

    init(store: PortfolioStore) { self.store = store }

    func start(suspended: Bool) { calls.append(.start(suspended: suspended)) }
    func suspend() { calls.append(.suspend) }
    func resume() { calls.append(.resume) }
    func resetLocalData() async throws {
        calls.append(.reset)
        try await store.removeAllRecords()
    }
    func uploadAllRecords() async throws {
        calls.append(.uploadAll)
        try await store.flagAllForUpload()
    }
    func syncNow() { calls.append(.syncNow) }
}

final class AccountStatusBox: @unchecked Sendable {
    var value: SyncAccountStatus
    init(_ value: SyncAccountStatus) { self.value = value }
}

@MainActor @Suite(.serialized) struct SyncControllerTests {
    private func setUp(status: SyncAccountStatus = .available, defaults: UserDefaults? = nil)
        async throws -> (SyncController, FakeSyncBackend, PortfolioRepository, AccountStatusBox) {
        let repo = try await makeRepository()
        let backend = FakeSyncBackend(store: repo.store)
        let box = AccountStatusBox(status)
        let suite = defaults ?? UserDefaults(suiteName: "yana.tests.\(UUID().uuidString)")!
        let controller = SyncController.make(store: repo.store, backend: backend, defaults: suite,
                                             now: { Date(timeIntervalSince1970: 1_729_300_000) },
                                             accountStatus: { box.value })
        await controller.start()
        return (controller, backend, repo, box)
    }

    @Test func startsAndResumesWhenAvailable() async throws {
        let (controller, backend, _, _) = try await setUp()
        #expect(await backend.calls == [.start(suspended: false), .resume])
        #expect(controller.status.state == .upToDate && controller.status.canSyncNow)
    }

    @Test func noAccountWorksLocallyAndShowsWhy() async throws {
        let (controller, backend, repo, _) = try await setUp(status: .noAccount)
        try await repo.createPortfolio(PortfolioDraft(name: "Offline"))
        await controller.refreshCounts()
        #expect(controller.status.state == .off)
        #expect(controller.status.reason == SyncAccountStatus.noAccount.reason)
        #expect(controller.status.pendingUploads == 1)
        await controller.syncNow()
        #expect(!(await backend.calls).contains(.syncNow))
    }

    @Test func accountBecomingAvailableResumesSync() async throws {
        let (controller, backend, _, box) = try await setUp(status: .temporarilyUnavailable)
        box.value = .available
        await controller.refreshAccountStatus()
        #expect(await backend.calls.last == .resume)
        #expect(controller.status.canSyncNow)
    }

    @Test func signInUploadsEverything() async throws {
        let (controller, backend, repo, _) = try await setUp(status: .noAccount)
        let p = try await repo.createPortfolio(PortfolioDraft(name: "Made while signed out"))
        let key = RecordKey(entity: .portfolio, id: p.id)
        try await repo.coordinator.didUpload(key, version: try #require(try await repo.store.record(for: key)).version)

        await controller.handle(.account(.signedIn))
        #expect(await backend.calls.last == .uploadAll)
        #expect(try await repo.store.keysNeedingUpload() == [key])
        #expect(controller.status.pendingUploads == 1)
    }

    @Test(arguments: [SyncAccountEvent.signedOut, .switchedAccounts])
    func accountChangeWithUnsentChangesWarnsThenRemoves(_ event: SyncAccountEvent) async throws {
        let (controller, backend, repo, _) = try await setUp()
        try await repo.createPortfolio(PortfolioDraft(name: "Account A"))
        try await repo.createPortfolio(PortfolioDraft(name: "Account A 2"))
        var changed = 0
        controller.onRecordsChanged = { changed += 1 }

        await controller.handle(.account(event))
        #expect(controller.unsentChangesWarning == 2)
        #expect(await backend.calls.last == .suspend)
        #expect(controller.status.state == .off && !controller.status.canSyncNow)
        // Nothing is removed before the person acknowledges the warning.
        #expect(try await repo.store.portfolios().count == 2)

        await controller.acknowledgeAccountChange()
        #expect(controller.unsentChangesWarning == nil)
        #expect(try await repo.store.portfolios().isEmpty)
        #expect(Array(await backend.calls.suffix(2)) == [.reset, .resume])
        #expect(changed == 1)
        #expect(controller.status.pendingUploads == 0)
        #expect(controller.status.state == (event == .signedOut ? .off : .upToDate))
    }

    @Test func accountChangeWithNothingPendingRemovesImmediately() async throws {
        let (controller, backend, repo, _) = try await setUp()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "Synced"))
        let key = RecordKey(entity: .portfolio, id: p.id)
        try await repo.coordinator.didUpload(key, version: try #require(try await repo.store.record(for: key)).version)

        await controller.handle(.account(.switchedAccounts))
        #expect(controller.unsentChangesWarning == nil)
        #expect(try await repo.store.portfolios().isEmpty)
        #expect(Array(await backend.calls.suffix(3)) == [.suspend, .reset, .resume])
    }

    @Test func unacknowledgedWarningSurvivesRelaunch() async throws {
        let defaults = UserDefaults(suiteName: "yana.tests.\(UUID().uuidString)")!
        let (first, _, repo, _) = try await setUp(defaults: defaults)
        try await repo.createPortfolio(PortfolioDraft(name: "Unsent"))
        await first.handle(.account(.signedOut))
        #expect(first.unsentChangesWarning == 1)

        // Relaunch: the warning is shown again and the engine starts suspended.
        let backend = FakeSyncBackend(store: repo.store)
        let relaunched = SyncController.make(store: repo.store, backend: backend, defaults: defaults, now: { Date() },
                                             accountStatus: { .available })
        await relaunched.start()
        #expect(relaunched.unsentChangesWarning == 1)
        #expect(await backend.calls == [.start(suspended: true)])
        await relaunched.acknowledgeAccountChange()
        #expect(try await repo.store.portfolios().isEmpty)
        #expect(defaults.object(forKey: "sync.pendingAccountChange") == nil)
    }

    @Test func cycleWithoutIssuesRecordsLastSync() async throws {
        let (controller, _, _, _) = try await setUp()
        await controller.handle(.fetchStarted)
        #expect(controller.status.state == .syncing)
        await controller.handle(.fetchFinished)
        #expect(controller.status.state == .upToDate)
        #expect(controller.status.lastSuccessfulSync == Date(timeIntervalSince1970: 1_729_300_000))
    }

    @Test func offlineIssuePersistsUntilACleanCycle() async throws {
        let (controller, _, repo, _) = try await setUp()
        try await repo.createPortfolio(PortfolioDraft(name: "A"))
        try await repo.createPortfolio(PortfolioDraft(name: "B"))
        await controller.handle(.sendStarted)
        await controller.handle(.issue(.offline))
        await controller.handle(.sendFinished)
        #expect(controller.status.state == .offline)
        #expect(controller.status.summary == "Offline — 2 changes waiting to upload")
        #expect(controller.status.lastSuccessfulSync == nil)

        await controller.handle(.sendStarted)
        await controller.handle(.sendFinished)
        #expect(controller.status.state == .pendingChanges)
        #expect(controller.status.lastSuccessfulSync != nil)
    }

    @Test func errorShowsReason() async throws {
        let (controller, _, _, _) = try await setUp()
        await controller.handle(.issue(.failed(reason: "Your iCloud storage is full.")))
        #expect(controller.status.state == .error && controller.status.reason == "Your iCloud storage is full.")
    }

    @Test func syncNowClearsTheLastIssueAndRuns() async throws {
        let (controller, backend, _, _) = try await setUp()
        await controller.handle(.issue(.offline))
        await controller.syncNow()
        #expect(await backend.calls.last == .syncNow)
        #expect(controller.status.state == .upToDate)
    }

    @Test func remoteChangesNotifyAndErasedServerDataRemovesLocalCopies() async throws {
        let (controller, _, repo, _) = try await setUp()
        try await repo.createPortfolio(PortfolioDraft(name: "P"))
        var changed = 0
        controller.onRecordsChanged = { changed += 1 }
        await controller.handle(.recordsChanged)
        #expect(changed == 1)
        await controller.handle(.serverDataErased)
        #expect(try await repo.store.portfolios().isEmpty && changed == 2)
    }

    @Test func readOnlyNoticeCountsLockedRecords() async throws {
        let (controller, _, repo, _) = try await setUp()
        let p = try await repo.createPortfolio(PortfolioDraft(name: "P"))
        var future = p
        future.version = p.version.bumped(at: p.version.modifiedAt.addingTimeInterval(60), deviceID: UUID())
        var json = try JSONSerialization.jsonObject(with: PayloadCodec.encode(future)) as! [String: Any]
        json["schemaVersion"] = 2
        try await repo.coordinator.receive(try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
        await controller.refreshCounts()
        #expect(controller.status.readOnlyNotice?.hasPrefix("1 item") == true)
    }
}
