import XCTest
@testable import GameCore

/// Exporters tests — run-directory isolation and timestamp collisions (audit BH-02).
final class ExporterTests: XCTestCase {

    private func makeTempExporters() throws -> (Exporters, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aoecard-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (Exporters(outputRoot: tmp), tmp)
    }

    // MARK: - BH-02: run-dir timestamp collision must not overwrite prior runs

    /// Two `makeRunDir` calls with the SAME minute-granularity timestamp must
    /// return DIFFERENT directories so the second run does not overwrite the
    /// first. Before the fix, both calls returned the same path and the second
    /// run's games.csv clobbered the first (silent data loss).
    func testMakeRunDirCollidesSafelyWithSuffix() throws {
        let (exporters, root) = try makeTempExporters()
        let stamp = "20260101_1200"

        let dir1 = try exporters.makeRunDir(timestamp: stamp)
        // Plant a marker file to prove the first run survives the second.
        let marker1 = dir1.appendingPathComponent("games.csv")
        try "run-1-data".write(to: marker1, atomically: true, encoding: .utf8)

        let dir2 = try exporters.makeRunDir(timestamp: stamp)
        let marker2 = dir2.appendingPathComponent("games.csv")
        try "run-2-data".write(to: marker2, atomically: true, encoding: .utf8)

        // The two directories MUST differ.
        XCTAssertNotEqual(dir1.path, dir2.path,
            "makeRunDir collision: same-timestamp runs returned the same path; second would overwrite first")
        // Both run data must survive.
        let survived1 = try String(contentsOf: marker1, encoding: .utf8)
        XCTAssertEqual(survived1, "run-1-data",
            "first run's data was overwritten by the second run")
        // The second dir lives under the same root.
        XCTAssertTrue(dir2.path.hasPrefix(root.path))

        // Cleanup
        try? FileManager.default.removeItem(at: root)
    }

    /// Different timestamps still produce their natural paths (no spurious suffix).
    func testMakeRunDirDifferentTimestampsNoSuffix() throws {
        let (exporters, root) = try makeTempExporters()
        let dirA = try exporters.makeRunDir(timestamp: "20260101_1200")
        let dirB = try exporters.makeRunDir(timestamp: "20260101_1201")
        XCTAssertNotEqual(dirA.path, dirB.path)
        XCTAssertTrue(dirA.lastPathComponent == "run_20260101_1200")
        XCTAssertTrue(dirB.lastPathComponent == "run_20260101_1201")
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - REL-04: collision suffix exhaustion must throw, not loop forever

    /// The collision guard caps suffixes at 9999. Pre-creating 9999 sibling
    /// directories must cause the 10000th `makeRunDir` to throw rather than
    /// loop indefinitely or silently reuse a path. Before this test, the cap
    /// existed but was unverified.
    func testMakeRunDirThrowsAfterSuffixExhaustion() throws {
        let (exporters, root) = try makeTempExporters()
        let stamp = "20260101_1300"

        // Pre-create all 10000 slots: the natural name + _1.._9999.
        // Use lightweight empty dirs to keep the test fast enough.
        for suffix in 0...9999 {
            let name = suffix == 0 ? "run_\(stamp)" : "run_\(stamp)_\(suffix)"
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name),
                withIntermediateDirectories: true)
        }

        // The 10001st call must throw (guard: suffix <= 9999).
        XCTAssertThrowsError(try exporters.makeRunDir(timestamp: stamp),
            "makeRunDir must throw after exhausting the 9999-suffix cap, not loop forever") { error in
            // The thrown error should be the guard's NSError.
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "Exporters",
                "expected the Exporters-domain exhaustion error")
        }

        try? FileManager.default.removeItem(at: root)
    }
}
