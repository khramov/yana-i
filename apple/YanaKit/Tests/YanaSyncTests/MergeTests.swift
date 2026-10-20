import Foundation
import Testing
import YanaDomain
@testable import YanaSync

private func header(_ rev: Int64, _ seconds: Double = 0, _ device: UUID = deviceA, deleted: Bool = false,
                    schema: Int = 1) -> PayloadHeader {
    PayloadHeader(schemaVersion: schema, entity: .transaction, id: Sample.transaction.id,
                  version: RecordVersion(revision: rev, modifiedAt: t0.addingTimeInterval(seconds), deviceID: device),
                  deleted: deleted)
}

private func local(_ h: PayloadHeader) -> LocalRecordState { LocalRecordState(version: h.version) }

/// Both devices apply the other's version through `decide`; they must end with the same winner.
private func converge(_ a: PayloadHeader, _ b: PayloadHeader) -> (onA: PayloadHeader, onB: PayloadHeader) {
    let onA = Merge.decide(local: local(a), incoming: b) == .applyIncoming ? b : a
    let onB = Merge.decide(local: local(b), incoming: a) == .applyIncoming ? a : b
    return (onA, onB)
}

@Suite struct MergeMatrixTests {
    @Test func unknownRecordIsApplied() {
        #expect(Merge.decide(local: nil, incoming: header(1)) == .applyIncoming)
    }

    @Test func higherRevisionWinsUpdateVsUpdate() {
        // A edited twice (rev 3) while B edited once (rev 2) from the same base.
        let a = header(3, 10, deviceA), b = header(2, 50, deviceB)
        #expect(Merge.decide(local: local(b), incoming: a) == .applyIncoming)
        #expect(Merge.decide(local: local(a), incoming: b) == .keepLocal)
        let r = converge(a, b)
        #expect(r.onA == a && r.onB == a)
    }

    @Test func deleteBeatsStaleUpdateInBothOrders() {
        let staleEdit = header(2, 5, deviceB)
        let delete = header(3, 1, deviceA, deleted: true)
        #expect(Merge.decide(local: local(staleEdit), incoming: delete) == .applyIncoming)
        #expect(Merge.decide(local: local(delete), incoming: staleEdit) == .keepLocal)
        let r = converge(delete, staleEdit)
        #expect(r.onA.deleted && r.onB.deleted)
    }

    @Test func newerEditBeatsOlderDelete() {
        // Re-creation over a known tombstone bumps above it, so it wins everywhere.
        let delete = header(3, 0, deviceA, deleted: true)
        let recreate = header(4, 1, deviceB)
        let r = converge(delete, recreate)
        #expect(!r.onA.deleted && !r.onB.deleted)
    }

    @Test func equalRevisionsTieBreakOnTimestamp() {
        let earlier = header(2, 1, deviceB), later = header(2, 2, deviceA)
        let r = converge(earlier, later)
        #expect(r.onA == later && r.onB == later)
    }

    @Test func equalRevisionAndTimestampTieBreakOnDevice() {
        let a = header(2, 1, deviceA), b = header(2, 1, deviceB)
        let r = converge(a, b)
        #expect(r.onA == b && r.onB == b)
    }

    @Test func identicalVersionKeepsLocal() {
        #expect(Merge.decide(local: local(header(2)), incoming: header(2)) == .keepLocal)
    }

    @Test func newerSchemaIsDeferredNotApplied() {
        #expect(Merge.decide(local: local(header(1)), incoming: header(2, schema: 2)) == .deferUnknownSchema)
        #expect(Merge.decide(local: nil, incoming: header(1, schema: 2)) == .deferUnknownSchema)
    }

    @Test func staleNewerSchemaIsIgnored() {
        #expect(Merge.decide(local: local(header(5)), incoming: header(2, schema: 2)) == .keepLocal)
    }

    @Test func pendingNewerPayloadOutranksOlderIncoming() {
        let state = LocalRecordState(version: header(1).version, pendingRemoteVersion: header(4).version)
        #expect(Merge.decide(local: state, incoming: header(3)) == .keepLocal)
        #expect(Merge.decide(local: state, incoming: header(5)) == .applyIncoming)
    }
}

@Suite struct LocalEditVersionTests {
    @Test func firstSaveIsRevisionOne() {
        #expect(Merge.localEditVersion(stored: nil, now: t0, deviceID: deviceA)
                == RecordVersion(revision: 1, modifiedAt: t0, deviceID: deviceA))
    }

    @Test func editBumpsStoredRevision() {
        let stored = LocalRecordState(version: RecordVersion(revision: 7, modifiedAt: t0, deviceID: deviceB))
        let v = Merge.localEditVersion(stored: stored, now: t0.addingTimeInterval(9), deviceID: deviceA)
        #expect(v == RecordVersion(revision: 8, modifiedAt: t0.addingTimeInterval(9), deviceID: deviceA))
    }

    @Test func recreationOverTombstoneOutranksIt() {
        let tombstone = header(5, 0, deviceB, deleted: true)
        let v = Merge.localEditVersion(stored: local(tombstone), now: t0, deviceID: deviceA)
        let incoming = PayloadHeader(schemaVersion: 1, entity: .transaction, id: tombstone.id, version: v, deleted: false)
        #expect(Merge.decide(local: local(tombstone), incoming: incoming) == .applyIncoming)
    }
}
