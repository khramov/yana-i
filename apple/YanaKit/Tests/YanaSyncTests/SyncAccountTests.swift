import Foundation
import Testing
@testable import YanaSync

@Suite struct SyncAccountMachineTests {
    @Test func becomingAvailableResumesTheOutbox() {
        var m = SyncAccountMachine(status: .noAccount)
        #expect(!m.canSync)
        #expect(m.handle(.statusChanged(.available), pendingUploads: 2) == [.requeueOutbox])
        #expect(m.canSync)
        // Already available: nothing to resume.
        #expect(m.handle(.statusChanged(.available), pendingUploads: 2) == [])
    }

    @Test(arguments: [SyncAccountStatus.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine, .unsupportedBuild])
    func unavailableStatusesStopSyncAndExplainWhy(_ status: SyncAccountStatus) {
        var m = SyncAccountMachine(status: .available)
        #expect(m.handle(.statusChanged(status), pendingUploads: 0) == [])
        #expect(!m.canSync)
        #expect(m.status.reason?.isEmpty == false)
        #expect(m.phase == .active)
    }

    @Test func noAccountReasonSaysWhereToEnableICloud() {
        #expect(SyncAccountStatus.noAccount.reason!.contains("System Settings"))
        #expect(SyncAccountStatus.available.reason == nil)
    }

    @Test func signInUploadsRecordsCreatedWhileSignedOut() {
        var m = SyncAccountMachine(status: .noAccount)
        #expect(m.handle(.signedIn, pendingUploads: 3) == [.uploadAllRecords])
        #expect(m.status == .available && m.canSync)
    }

    @Test(arguments: [SyncAccountEvent.signedOut, .switchedAccounts])
    func accountChangeWithUnsentChangesWarnsBeforeRemoving(_ event: SyncAccountEvent) {
        var m = SyncAccountMachine(status: .available)
        #expect(m.handle(event, pendingUploads: 2) == [.suspendSync, .warnAboutUnsentChanges(count: 2)])
        #expect(m.phase == .awaitingAcknowledgement(unsentChanges: 2))
        #expect(!m.canSync)

        // Nothing is removed or synced until the person acknowledges.
        #expect(m.handle(.signedIn, pendingUploads: 2) == [])
        #expect(m.handle(.statusChanged(.available), pendingUploads: 2) == [])
        #expect(m.handle(.localDataRemoved, pendingUploads: 2) == [])
        #expect(!m.canSync)

        #expect(m.handle(.warningAcknowledged, pendingUploads: 2) == [.removeLocalDataAndResetEngine])
        #expect(m.phase == .removingLocalData && !m.canSync)
        #expect(m.handle(.localDataRemoved, pendingUploads: 0) == [.resumeSync])
        #expect(m.phase == .active)
    }

    @Test func switchWithNothingPendingRemovesWithoutWarning() {
        var m = SyncAccountMachine(status: .available)
        #expect(m.handle(.switchedAccounts, pendingUploads: 0) == [.suspendSync, .removeLocalDataAndResetEngine])
        #expect(m.status == .available && !m.canSync)
        #expect(m.handle(.localDataRemoved, pendingUploads: 0) == [.resumeSync])
        #expect(m.canSync)
    }

    @Test func signOutLeavesSyncOffAfterRemoval() {
        var m = SyncAccountMachine(status: .available)
        _ = m.handle(.signedOut, pendingUploads: 0)
        _ = m.handle(.localDataRemoved, pendingUploads: 0)
        #expect(m.status == .noAccount && !m.canSync)
    }

    @Test func repeatedAccountChangeWhileWaitingKeepsTheFirstWarning() {
        var m = SyncAccountMachine(status: .available)
        _ = m.handle(.signedOut, pendingUploads: 4)
        #expect(m.handle(.switchedAccounts, pendingUploads: 4) == [])
        #expect(m.phase == .awaitingAcknowledgement(unsentChanges: 4))
    }

    @Test func strayAcknowledgementIsIgnored() {
        var m = SyncAccountMachine(status: .available)
        #expect(m.handle(.warningAcknowledged, pendingUploads: 0) == [])
        #expect(m.phase == .active)
    }

    @Test func restoredWaitingPhaseStillBlocksSync() {
        // The app quit while the warning was showing; it relaunches in the same phase.
        let m = SyncAccountMachine(status: .available, phase: .awaitingAcknowledgement(unsentChanges: 1))
        #expect(!m.canSync)
    }
}

@Suite struct SyncStatusTests {
    private let available = SyncAccountMachine(status: .available)
    private let lastSync = Date(timeIntervalSince1970: 1_729_300_000)

    @Test func upToDate() {
        let s = SyncStatus(account: available, activity: SyncActivity(lastSuccessfulSync: lastSync))
        #expect(s.state == .upToDate && s.summary == "Up to date")
        #expect(s.lastSuccessfulSync == lastSync && s.reason == nil && s.canSyncNow)
    }

    @Test func syncingWhileFetchingOrSending() {
        #expect(SyncStatus(account: available, activity: SyncActivity(isFetching: true)).state == .syncing)
        let s = SyncStatus(account: available, activity: SyncActivity(isSending: true, pendingUploads: 3, lastIssue: .offline))
        #expect(s.state == .syncing && s.summary == "Syncing…")
    }

    @Test func pendingChanges() {
        let s = SyncStatus(account: available, activity: SyncActivity(pendingUploads: 1))
        #expect(s.state == .pendingChanges && s.summary == "1 change waiting to upload")
    }

    @Test func offlineWithTwoPendingChangesShowsCountAndLastSync() {
        let s = SyncStatus(account: available,
                           activity: SyncActivity(pendingUploads: 2, lastSuccessfulSync: lastSync, lastIssue: .offline))
        #expect(s.state == .offline)
        #expect(s.summary == "Offline — 2 changes waiting to upload")
        #expect(s.lastSuccessfulSync == lastSync && s.reason != nil)
    }

    @Test func errorCarriesItsReason() {
        let s = SyncStatus(account: available, activity: SyncActivity(lastIssue: .failed(reason: "iCloud storage is full.")))
        #expect(s.state == .error && s.reason == "iCloud storage is full." && s.summary == "Sync error")
    }

    @Test func noAccountIsOffWithReason() {
        let s = SyncStatus(account: SyncAccountMachine(status: .noAccount), activity: SyncActivity(pendingUploads: 2))
        #expect(s.state == .off && s.reason == SyncAccountStatus.noAccount.reason)
        #expect(s.summary == "Sync off — 2 changes waiting to upload" && !s.canSyncNow)
    }

    @Test func accountChangeInProgressIsOff() {
        let m = SyncAccountMachine(status: .available, phase: .removingLocalData)
        let s = SyncStatus(account: m, activity: SyncActivity(isFetching: true))
        #expect(s.state == .off && s.reason!.contains("previous iCloud account") && !s.canSyncNow)
    }

    @Test func readOnlyNoticeForRecordsNeedingAnUpdate() {
        #expect(SyncStatus(account: available, activity: SyncActivity()).readOnlyNotice == nil)
        let one = SyncStatus(account: available, activity: SyncActivity(recordsAwaitingAppUpdate: 1))
        #expect(one.readOnlyNotice!.hasPrefix("1 item") && one.readOnlyNotice!.contains("Update the app"))
        #expect(SyncStatus(account: available, activity: SyncActivity(recordsAwaitingAppUpdate: 3)).readOnlyNotice!.hasPrefix("3 items"))
    }
}
