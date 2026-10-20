import Foundation
import Testing
import YanaDomain
@testable import YanaSync

@Suite struct PayloadCodecTests {
    /// Set YANA_RECORD_GOLDEN=1 to rewrite the golden files from the current encoder.
    static let recording = ProcessInfo.processInfo.environment["YANA_RECORD_GOLDEN"] == "1"

    func goldenURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Golden", withExtension: nil)!.appendingPathComponent("\(name).json")
    }

    @Test(arguments: Sample.all.map(\.0))
    func matchesGoldenBytes(_ name: String) throws {
        let record = Sample.all.first { $0.0 == name }!.1
        let data = PayloadCodec.encode(record)
        if Self.recording {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Golden/\(name).json")
            try data.write(to: source)
            return
        }
        let golden = try Data(contentsOf: goldenURL(name))
        #expect(data == golden, "\(String(decoding: data, as: UTF8.self))")
    }

    @Test(arguments: Sample.all.map(\.0))
    func roundTrips(_ name: String) throws {
        let record = Sample.all.first { $0.0 == name }!.1
        #expect(try PayloadCodec.decode(PayloadCodec.encode(record)) == record)
        if !Self.recording {
            #expect(try PayloadCodec.decode(Data(contentsOf: goldenURL(name))) == record)
        }
    }

    @Test func headerReadsEnvelope() throws {
        let h = try PayloadCodec.header(PayloadCodec.encode(Sample.goalTombstone))
        #expect(h.schemaVersion == 1)
        #expect(h.entity == .goal)
        #expect(h.id == Sample.goalTombstone.id)
        #expect(h.version == Sample.goalTombstone.version)
        #expect(h.deleted)
    }

    @Test func newerSchemaIsRejectedButHeaderStillReadable() throws {
        var object = try JSONSerialization.jsonObject(with: PayloadCodec.encode(Sample.portfolio)) as! [String: Any]
        object["schemaVersion"] = 2
        var fields = object["fields"] as! [String: Any]
        fields["brandNewField"] = "x"
        object["fields"] = fields
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: PayloadError.unsupportedSchema(2)) { try PayloadCodec.decode(data) }
        #expect(try PayloadCodec.header(data).version == Sample.portfolio.version)
    }

    @Test func malformedPayloadsNameTheField() throws {
        var object = try JSONSerialization.jsonObject(with: PayloadCodec.encode(Sample.transaction)) as! [String: Any]
        var fields = object["fields"] as! [String: Any]
        fields["fee"] = "1,5"
        object["fields"] = fields
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: PayloadError.malformed("fields.fee")) { try PayloadCodec.decode(data) }
        #expect(throws: PayloadError.malformed("not a JSON object")) { try PayloadCodec.decode(Data("[]".utf8)) }
    }

    @Test func decimalsAreCanonicalStrings() {
        #expect(PayloadCodec.decimal(dec("1.50")) == "1.5")
        #expect(PayloadCodec.decimal(dec("-0.0001")) == "-0.0001")
        #expect(PayloadCodec.decimal(dec("1000000")) == "1000000")
    }
}
