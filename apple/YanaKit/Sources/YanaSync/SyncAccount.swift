import Foundation

/// Whether the sync backend's account can be used, and if not, why.
public enum SyncAccountStatus: Equatable, Sendable {
    case available
    /// No account is signed in, or iCloud is turned off for the app.
    case noAccount
    /// Screen Time or device management blocks access.
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    /// This build carries no iCloud entitlement (an unsigned development build).
    case unsupportedBuild

    /// Why sync is off, or `nil` when the account is available.
    public var reason: String? {
        switch self {
        case .available:
            return nil
        case .noAccount:
            return "Sync is off because no iCloud account is available to Yana. Sign in to iCloud, or turn on iCloud "
                + "for Yana, in System Settings › Apple Account › iCloud."
        case .restricted:
            return "iCloud access is restricted on this Mac by Screen Time or device management."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Sync resumes automatically."
        case .couldNotDetermine:
            return "The iCloud account status could not be determined. Sync resumes when it can be checked."
        case .unsupportedBuild:
            return "This build of Yana is not signed for iCloud, so sync is off."
        }
    }
}

/// Account-level input to the sync state machine.
public enum SyncAccountEvent: Equatable, Sendable {
    case statusChanged(SyncAccountStatus)
    /// An account became available where there was none.
    case signedIn
    case signedOut
    /// A different account replaced the previous one.
    case switchedAccounts
    /// The person dismissed the pending-changes warning shown after a sign-out or account switch.
    case warningAcknowledged
    /// The previous account's records and sync state have been removed from this Mac.
    case localDataRemoved
}

/// What the app must do in response to an account event.
public enum SyncAccountEffect: Equatable, Sendable {
    /// Re-queue records already flagged for upload (sync resumed).
    case requeueOutbox
    /// Flag every local record for upload and queue it: the records were created while signed out and now
    /// belong to the account that just signed in.
    case uploadAllRecords
    /// Stop sending and applying records until the previous account's data is gone.
    case suspendSync
    /// Show a blocking warning that this many changes were never uploaded and will be removed.
    case warnAboutUnsentChanges(count: Int)
    /// Delete every synchronized record and the engine state, then start over for the current account.
    case removeLocalDataAndResetEngine
    case resumeSync
}

/// The account side of sync: keeps one account's records from ever reaching another account.
///
/// After a sign-out or account switch, sync is suspended until the previous account's records are removed. If
/// changes were still waiting to upload, the person is warned first and removal waits for them to acknowledge it.
public struct SyncAccountMachine: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case active
        /// The account changed with this many changes not uploaded; the warning is showing.
        case awaitingAcknowledgement(unsentChanges: Int)
        case removingLocalData
    }

    public private(set) var status: SyncAccountStatus
    public private(set) var phase: Phase

    public init(status: SyncAccountStatus = .couldNotDetermine, phase: Phase = .active) {
        self.status = status
        self.phase = phase
    }

    /// Records may be sent and applied.
    public var canSync: Bool { status == .available && phase == .active }

    /// `pendingUploads` is the current number of records flagged for upload.
    public mutating func handle(_ event: SyncAccountEvent, pendingUploads: Int) -> [SyncAccountEffect] {
        switch event {
        case .statusChanged(let new):
            let wasSyncable = canSync
            status = new
            return !wasSyncable && canSync ? [.requeueOutbox] : []

        case .signedIn:
            status = .available
            return phase == .active ? [.uploadAllRecords] : []

        case .signedOut, .switchedAccounts:
            if event == .signedOut { status = .noAccount }
            switch phase {
            case .awaitingAcknowledgement, .removingLocalData:
                return []
            case .active:
                if pendingUploads > 0 {
                    phase = .awaitingAcknowledgement(unsentChanges: pendingUploads)
                    return [.suspendSync, .warnAboutUnsentChanges(count: pendingUploads)]
                }
                phase = .removingLocalData
                return [.suspendSync, .removeLocalDataAndResetEngine]
            }

        case .warningAcknowledged:
            guard case .awaitingAcknowledgement = phase else { return [] }
            phase = .removingLocalData
            return [.removeLocalDataAndResetEngine]

        case .localDataRemoved:
            guard phase == .removingLocalData else { return [] }
            phase = .active
            return [.resumeSync]
        }
    }
}
