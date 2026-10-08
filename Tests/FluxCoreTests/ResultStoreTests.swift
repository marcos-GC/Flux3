import XCTest
@testable import FluxCore

final class ResultStoreTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func record(_ id: String, prompt: String, date: Date) -> GenerationRecord {
        GenerationRecord(
            taskID: id, endpoint: BFLEndpoint.flux3Image.path, model: "FLUX 3 Image", createdAt: date,
            prompt: prompt, sentPrompt: prompt,
            parameters: .object(["resolution": .string("2k"), "aspect_ratio": .string("3:2")]),
            cost: 4, region: "eu", referenceCount: 2
        )
    }

    func testSaveAndLoadRoundTrip() throws {
        let older = Date(timeIntervalSince1970: 1_790_000_000)
        let newer = older.addingTimeInterval(3600)
        let a = try ResultStore.save(data: Data([1, 2, 3]), mimeType: "image/jpeg", sourceURL: nil,
                                     base: base, prefix: "flux3-image", index: 0, record: record("aaaaaaaa1", prompt: "salón", date: older))
        _ = try ResultStore.save(data: Data([4, 5]), mimeType: "image/png", sourceURL: nil,
                                 base: base, prefix: "flux3-image", index: 1, record: record("bbbbbbbb2", prompt: "cocina", date: newer))

        XCTAssertEqual(a.fileURL.pathExtension, "jpg")
        XCTAssertTrue(a.fileURL.deletingLastPathComponent().lastPathComponent.hasPrefix("20"))

        let loaded = ResultStore.loadAll(base: base)
        XCTAssertEqual(loaded.map(\.record.prompt), ["cocina", "salón"]) // más reciente primero
        XCTAssertEqual(loaded.last?.record.referenceCount, 2)
        XCTAssertEqual(loaded.last?.fileURL.lastPathComponent, a.fileURL.lastPathComponent)
    }

    func testIgnoresOrphansAndForeignJSON() throws {
        let saved = try ResultStore.save(data: Data([1]), mimeType: "image/jpeg", sourceURL: nil,
                                         base: base, prefix: "x", index: 0, record: record("cccccccc3", prompt: "p", date: Date()))
        try FileManager.default.removeItem(at: saved.fileURL) // el archivo desaparece
        try Data(#"{"hola":"mundo"}"#.utf8).write(to: base.appendingPathComponent("otro.json"))
        XCTAssertTrue(ResultStore.loadAll(base: base).isEmpty)
    }

    func testReuseSettingsFromParameters() {
        let s = Flux3ImageSettings(parameters: .object([
            "aspect_ratio": .string("2:3"), "resolution": .string("4k"),
            "safety_tolerance": .number(3), "grounding": .bool(false),
        ]))
        XCTAssertEqual(s.aspectRatio, "2:3")
        XCTAssertEqual(s.resolution, "4k")
        XCTAssertEqual(s.safetyTolerance, 3)
        XCTAssertFalse(s.grounding)

        let defaults = Flux3ImageSettings(parameters: .object(["prompt": .string("x")]))
        XCTAssertEqual(defaults, Flux3ImageSettings())
    }
}
