import Foundation

/// The most recent sync problem, classified for display.
public enum SyncIssue: Equatable, Sendable {
    /// The network or the service could not be reached; sync retries on its own.
    case offline
    case failed(reason: String)
}

/// What the sync transport and the store report, gathered in one value.
public struct SyncActivity: Equatable, Sendable {
    public var isFetching = false
    public var isSending = false
    /// Records flagged for upload.
    public var pendingUploads = 0
    public var lastSuccessfulSync: Date?
    /// Cleared by the next successful fetch or send.
    public var lastIssue: SyncIssue?
    /// Records locked read-only behind a newer-schema payload.
    public var recordsAwaitingAppUpdate = 0

    public init(isFetching: Bool = false, isSending: Bool = false, pendingUploads: Int = 0, lastSuccessfulSync: Date? = nil,
                lastIssue: SyncIssue? = nil, recordsAwaitingAppUpdate: Int = 0) {
        self.isFetching = isFetching
        self.isSending = isSending
        self.pendingUploads = pendingUploads
        self.lastSuccessfulSync = lastSuccessfulSync
        self.lastIssue = lastIssue
        self.recordsAwaitingAppUpdate = recordsAwaitingAppUpdate
    }
}

/// The sync state shown to the person.
public struct SyncStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case upToDate
        case syncing
        case pendingChanges
        case offline
        /// No usable account, or sync paused for an account change.
        case off
        case error
    }

    public var state: State
    public var pendingUploads: Int
    public var lastSuccessfulSync: Date?
    /// Why sync is off, offline, or failing.
    public var reason: String?
    /// Shown while records from a newer app version are held read-only.
    public var readOnlyNotice: String?
    /// Whether Sync Now can do anything.
    public var canSyncNow: Bool

    public init(account: SyncAccountMachine, activity: SyncActivity) {
        pendingUploads = activity.pendingUploads
        lastSuccessfulSync = activity.lastSuccessfulSync
        readOnlyNotice = Self.readOnlyNotice(activity.recordsAwaitingAppUpdate)
        canSyncNow = account.canSync

        if account.phase != .active {
            state = .off
            reason = "Sync is paused while data from the previous iCloud account is removed from this Mac."
        } else if let accountReason = account.status.reason {
            state = .off
            reason = accountReason
        } else if activity.isFetching || activity.isSending {
            state = .syncing
            reason = nil
        } else {
            switch activity.lastIssue {
            case .offline:
                state = .offline
                reason = "iCloud can't be reached. Changes upload when the connection returns."
            case .failed(let why):
                state = .error
                reason = why
            case nil:
                state = activity.pendingUploads > 0 ? .pendingChanges : .upToDate
                reason = nil
            }
        }
    }

    /// One line for a status bar or Settings, e.g. "Offline — 2 changes waiting to upload".
    public var summary: String {
        let waiting = pendingUploads == 1 ? "1 change waiting to upload" : "\(pendingUploads) changes waiting to upload"
        switch state {
        case .upToDate: return "Up to date"
        case .syncing: return "Syncing…"
        case .pendingChanges: return waiting
        case .offline: return pendingUploads > 0 ? "Offline — \(waiting)" : "Offline"
        case .off: return pendingUploads > 0 ? "Sync off — \(waiting)" : "Sync off"
        case .error: return "Sync error"
        }
    }

    private static func readOnlyNotice(_ count: Int) -> String? {
        switch count {
        case 0: return nil
        case 1: return "1 item was changed by a newer version of Yana. Update the app to see and edit it."
        default: return "\(count) items were changed by a newer version of Yana. Update the app to see and edit them."
        }
    }
}
