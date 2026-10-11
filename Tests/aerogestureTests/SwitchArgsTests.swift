import XCTest
@testable import aerogesture

final class SwitchArgsTests: XCTestCase {
    func testPlain() {
        let (args, stdin) = AeroSpaceSocket.switchArgs(direction: .next, config: WorkspaceConfig(), nonEmptyWorkspaces: nil)
        XCTAssertEqual(args, ["workspace", "next"])
        XCTAssertEqual(stdin, "")
    }

    func testWrapAround() {
        var ws = WorkspaceConfig()
        ws.wrapAround = true
        let (args, _) = AeroSpaceSocket.switchArgs(direction: .prev, config: ws, nonEmptyWorkspaces: nil)
        XCTAssertEqual(args, ["workspace", "prev", "--wrap-around"])
    }

    func testSkipEmptyUsesStdin() {
        var ws = WorkspaceConfig()
        ws.skipEmpty = true
        let (args, stdin) = AeroSpaceSocket.switchArgs(direction: .next, config: ws, nonEmptyWorkspaces: "1\n3\n")
        XCTAssertEqual(args, ["workspace", "next", "--stdin"])
        XCTAssertEqual(stdin, "1\n3\n")
    }

    func testSkipEmptyFallsBackWhenListFails() {
        var ws = WorkspaceConfig()
        ws.skipEmpty = true
        for list in [nil, ""] {
            let (args, stdin) = AeroSpaceSocket.switchArgs(direction: .next, config: ws, nonEmptyWorkspaces: list)
            XCTAssertEqual(args, ["workspace", "next"])
            XCTAssertEqual(stdin, "")
        }
    }
}

final class ClientRequestTests: XCTestCase {
    func testEncodesExplicitNulls() throws {
        let json = try String(data: JSONEncoder().encode(ClientRequest(args: ["workspace", "next"])), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"windowId\":null"))
        XCTAssertTrue(json.contains("\"workspace\":null"))
    }
}
