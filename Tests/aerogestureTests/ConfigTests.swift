import XCTest
@testable import aerogesture

final class ConfigTests: XCTestCase {
    func testPartialFileKeepsDefaultsForMissingKeys() throws {
        let c = try Config.parse("[gesture]\nfingers = 4\n")
        XCTAssertEqual(c.gesture.fingers, 4)
        XCTAssertEqual(c.gesture.sensitivity, 1.0)
        XCTAssertTrue(c.gesture.naturalDirection)
        XCTAssertFalse(c.workspace.wrapAround)
    }

    func testMissingTableUsesDefaults() throws {
        let c = try Config.parse("[workspace]\nwrap_around = true\n")
        XCTAssertTrue(c.workspace.wrapAround)
        XCTAssertEqual(c.gesture.fingers, 3)
    }

    func testEmptyFileIsDefaults() throws {
        XCTAssertEqual(try Config.parse("").gesture.fingers, 3)
    }

    func testIntegerSensitivityIsAccepted() throws {
        XCTAssertEqual(try Config.parse("[gesture]\nsensitivity = 2\n").gesture.sensitivity, 2.0)
        XCTAssertEqual(try Config.parse("[gesture]\nsensitivity = 0.5\n").gesture.sensitivity, 0.5)
    }

    private func assertInvalid(_ toml: String, field: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Config.parse(toml), file: file, line: line) { error in
            guard case ConfigError.invalid(let f, _) = error else {
                return XCTFail("expected .invalid, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(f, field, file: file, line: line)
        }
    }

    func testInvalidFingers() {
        for n in [0, 1, 2, 6] {
            assertInvalid("[gesture]\nfingers = \(n)\n", field: "gesture.fingers")
        }
    }

    func testInvalidSensitivity() {
        for v in ["0.0", "-1.5", "inf", "nan"] {
            assertInvalid("[gesture]\nsensitivity = \(v)\n", field: "gesture.sensitivity")
        }
    }

    func testSyntaxErrorIsParseError() {
        XCTAssertThrowsError(try Config.parse("[gesture\n")) { error in
            guard case ConfigError.parse = error else { return XCTFail("got \(error)") }
        }
    }

    func testMissingFile() {
        XCTAssertThrowsError(try Config.load(from: URL(fileURLWithPath: "/nonexistent/aerogesture.toml"))) { error in
            guard case ConfigError.missing = error else { return XCTFail("got \(error)") }
        }
    }
}
