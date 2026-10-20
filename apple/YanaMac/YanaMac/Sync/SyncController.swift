import CloudKit
import Foundation
import Observation
import Security
import YanaSync

/// The parts of a sync backend the controller drives (`CloudKitSyncTransport` in the app, a fake in tests).
protocol SyncBackend: Sendable {
    func start(suspended: Bool) async throws
    func suspend() async
    func resume() async throws
    /// Removes every synchronized record and the backend state from this Mac.
    func resetLocalData() async throws
    func uploadAllRecords() async throws
    func syncNow() async
}

extension CloudKitSyncTransport: SyncBackend {}

/// Owns sync for the app: runs the account state machine, executes its effects, and publishes `SyncStatus`.
@MainActor @Observable
final class SyncController {
    private(set) var account: SyncAccountMachine
    private(set) var activity = SyncActivity()
    /// Set while the blocking "changes were not uploaded" warning must be shown.
    private(set) var unsentChangesWarning: Int?

    var status: SyncStatus { SyncStatus(account: account, activity: activity) }

    /// Called after records from another Mac were applied, or local records were removed.
    @ObservationIgnored var onRecordsChanged: @MainActor () -> Void = {}

    @ObservationIgnored private let store: PortfolioStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let accountStatus: @Sendable () async -> SyncAccountStatus
    @ObservationIgnored private var backend: (any SyncBackend)?
    @ObservationIgnored private var accountObserver: (any NSObjectProtocol)?

    private enum Key {
        static let lastSuccessfulSync = "sync.lastSuccessfulSync"
        /// Unsent-change count of an account change the person has not acknowledged yet.
        static let pendingAccountChange = "sync.pendingAccountChange"
    }

    init(store: PortfolioStore, defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() },
         accountStatus: @escaping @Sendable () async -> SyncAccountStatus) {
        self.store = store
        self.defaults = defaults
        self.now = now
        self.accountStatus = accountStatus
        let unsent = defaults.object(forKey: Key.pendingAccountChange) as? Int
        account = SyncAccountMachine(phase: unsent.map { .awaitingAcknowledgement(unsentChanges: $0) } ?? .active)
        unsentChangesWarning = unsent
        activity.lastSuccessfulSync = defaults.object(forKey: Key.lastSuccessfulSync) as? Date
    }

    /// The controller for this app: CloudKit when the build is entitled for it, otherwise sync stays off.
    static func live(store: PortfolioStore, coordinator: SyncCoordinator) -> SyncController {
        let identifier = AppConfiguration.cloudKitContainer
        guard hasCloudKitEntitlement, !identifier.isEmpty else {
            return SyncController(store: store, accountStatus: { .unsupportedBuild })
        }
        let container = CKContainer(identifier: identifier)
        let controller = SyncController(store: store, accountStatus: {
            (try? await container.accountStatus()).map(SyncAccountStatus.init) ?? .couldNotDetermine
        })
        controller.backend = CloudKitSyncTransport(database: container.privateCloudDatabase, store: store,
                                                   coordinator: coordinator) { [weak controller] event in
            await controller?.handle(event)
        }
        controller.accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil,
                                                                            queue: .main) { [weak controller] _ in
            Task { await controller?.refreshAccountStatus() }
        }
        return controller
    }

    /// For tests: a controller over a given backend.
    static func make(store: PortfolioStore, backend: any SyncBackend, defaults: UserDefaults,
                     now: @escaping @Sendable () -> Date,
                     accountStatus: @escaping @Sendable () async -> SyncAccountStatus) -> SyncController {
        let controller = SyncController(store: store, defaults: defaults, now: now, accountStatus: accountStatus)
        controller.backend = backend
        return controller
    }

    static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains("CloudKit") == true
    }

    // MARK: - Lifecycle

    func start() async {
        await refreshCounts()
        do {
            try await backend?.start(suspended: account.phase != .active)
        } catch {
            activity.lastIssue = .failed(reason: error.localizedDescription)
        }
        await refreshAccountStatus()
    }

    func refreshAccountStatus() async {
        await apply(.statusChanged(await accountStatus()))
    }

    /// Re-reads the outbox size and the number of read-only records. Call after local writes.
    func refreshCounts() async {
        activity.pendingUploads = (try? await store.keysNeedingUpload().count) ?? activity.pendingUploads
        activity.recordsAwaitingAppUpdate = (try? await store.keysAwaitingAppUpdate().count) ?? 0
    }

    func syncNow() async {
        guard account.canSync else { return }
        activity.lastIssue = nil
        await backend?.syncNow()
        await refreshCounts()
    }

    /// The person dismissed the unsent-changes warning: remove the previous account's data.
    func acknowledgeAccountChange() async {
        await apply(.warningAcknowledged)
    }

    // MARK: - Events

    func handle(_ event: CloudKitTransportEvent) async {
        switch event {
        case .account(let accountEvent):
            await apply(accountEvent)
        case .fetchStarted:
            beginCycle()
            activity.isFetching = true
        case .sendStarted:
            beginCycle()
            activity.isSending = true
        case .fetchFinished:
            activity.isFetching = false
            finishCycle()
        case .sendFinished:
            activity.isSending = false
            await refreshCounts()
            finishCycle()
        case .issue(let issue):
            issueDuringCycle = true
            activity.lastIssue = issue
        case .recordsChanged:
            await refreshCounts()
            onRecordsChanged()
        case .serverDataErased:
            await removeLocalData()
        }
    }

    @ObservationIgnored private var issueDuringCycle = false

    private func beginCycle() {
        if !activity.isFetching && !activity.isSending { issueDuringCycle = false }
    }

    /// When fetching and sending have both finished without a new issue, sync is healthy again.
    private func finishCycle() {
        guard !activity.isFetching, !activity.isSending, !issueDuringCycle else { return }
        activity.lastIssue = nil
        activity.lastSuccessfulSync = now()
        defaults.set(activity.lastSuccessfulSync, forKey: Key.lastSuccessfulSync)
    }

    private func apply(_ event: SyncAccountEvent) async {
        await refreshCounts()
        let effects = account.handle(event, pendingUploads: activity.pendingUploads)
        for effect in effects { await perform(effect) }
    }

    private func perform(_ effect: SyncAccountEffect) async {
        do {
            switch effect {
            case .requeueOutbox, .resumeSync:
                try await backend?.resume()
            case .uploadAllRecords:
                try await backend?.uploadAllRecords()
                await refreshCounts()
            case .suspendSync:
                await backend?.suspend()
            case .warnAboutUnsentChanges(let count):
                defaults.set(count, forKey: Key.pendingAccountChange)
                unsentChangesWarning = count
            case .removeLocalDataAndResetEngine:
                await removeLocalData()
            }
        } catch {
            activity.lastIssue = .failed(reason: error.localizedDescription)
        }
    }

    private func removeLocalData() async {
        do {
            if let backend {
                try await backend.resetLocalData()
            } else {
                try await store.removeAllRecords()
            }
        } catch {
            activity.lastIssue = .failed(reason: error.localizedDescription)
            return
        }
        defaults.removeObject(forKey: Key.pendingAccountChange)
        unsentChangesWarning = nil
        await refreshCounts()
        onRecordsChanged()
        await apply(.localDataRemoved)
    }
}
