import XCTest
@testable import GrokBuild

final class AcpTerminalHostTests: XCTestCase {
    func testParseCreateRequestRequiresCommand() {
        XCTAssertNil(AcpTerminalHost.parseCreateRequest([:]))
        XCTAssertNil(AcpTerminalHost.parseCreateRequest(["command": "   "]))
        let parsed = AcpTerminalHost.parseCreateRequest([
            "command": "npm",
            "args": ["test", "--coverage"],
            "cwd": "/tmp/project",
            "env": [["name": "NODE_ENV", "value": "test"]],
            "outputByteLimit": 4096
        ])
        XCTAssertEqual(parsed?.command, "npm")
        XCTAssertEqual(parsed?.args, ["test", "--coverage"])
        XCTAssertEqual(parsed?.cwd, "/tmp/project")
        XCTAssertEqual(parsed?.env["NODE_ENV"], "test")
        XCTAssertEqual(parsed?.byteLimit, 4096)
    }

    func testParseCreateRequestDefaultsByteLimit() {
        let parsed = AcpTerminalHost.parseCreateRequest(["command": "echo"])
        XCTAssertEqual(parsed?.byteLimit, AcpTerminalHost.defaultOutputByteLimit)
        XCTAssertEqual(parsed?.args, [])
    }

    func testResolveLaunchKeepsAbsoluteCommand() {
        let launch = AcpTerminalHost.resolveLaunch(command: "/bin/echo", args: ["hi"])
        XCTAssertEqual(launch.exe, "/bin/echo")
        XCTAssertEqual(launch.args, ["hi"])
    }

    func testSplitCommandLineKeepsQuotedScript() {
        XCTAssertEqual(
            AcpTerminalHost.splitCommandLine("bash -lc 'echo SHELL_OK && pwd'"),
            ["bash", "-lc", "echo SHELL_OK && pwd"]
        )
        XCTAssertEqual(
            AcpTerminalHost.splitCommandLine("/bin/bash -lc \"uname -s\""),
            ["/bin/bash", "-lc", "uname -s"]
        )
    }

    func testResolveLaunchSplitsBashLcCommandLine() {
        let launch = AcpTerminalHost.resolveLaunch(
            command: "bash -lc 'echo SHELL_OK && uname -s && pwd && whoami'",
            args: []
        )
        XCTAssertTrue(launch.exe.hasSuffix("/bash"), launch.exe)
        XCTAssertEqual(launch.args.first, "-lc")
        XCTAssertEqual(launch.args.last, "echo SHELL_OK && uname -s && pwd && whoami")
        XCTAssertFalse(launch.exe.contains(" "), "must not use the whole line as argv0")
    }

    func testResolveLaunchSplitsAbsoluteBashLcCommandLine() {
        let launch = AcpTerminalHost.resolveLaunch(
            command: "/bin/bash -lc 'echo hi'",
            args: []
        )
        XCTAssertEqual(launch.exe, "/bin/bash")
        XCTAssertEqual(launch.args, ["-lc", "echo hi"])
    }

    func testParseCreateRequestAcceptsCommandArrayAndEnvMap() {
        let parsed = AcpTerminalHost.parseCreateRequest([
            "command": ["bash", "-lc", "echo hi"],
            "env": ["FOO": "bar"]
        ])
        XCTAssertEqual(parsed?.command, "bash")
        XCTAssertEqual(parsed?.args, ["-lc", "echo hi"])
        XCTAssertEqual(parsed?.env["FOO"], "bar")
    }

    func testCreateBashLcReturnsOutput() {
        let host = AcpTerminalHost()
        defer { host.releaseAll() }
        let created = try! host.create(
            params: ["command": "bash -lc 'echo ACP-BASH-OK'"],
            defaultCwd: FileManager.default.temporaryDirectory
        )
        let id = created["terminalId"] as? String
        XCTAssertNotNil(id)

        let exited = expectation(description: "bash -lc exits")
        switch try! host.waitForExit(terminalId: id!) { payload in
            XCTAssertEqual(payload["exitCode"] as? Int, 0)
            exited.fulfill()
        } {
        case .alreadyExited(let payload):
            XCTAssertEqual(payload["exitCode"] as? Int, 0)
            exited.fulfill()
        case .pending:
            break
        }
        wait(for: [exited], timeout: 3)

        let snapshot = try! host.output(terminalId: id!)
        XCTAssertTrue((snapshot["output"] as? String)?.contains("ACP-BASH-OK") == true, "\(snapshot)")
        _ = try? host.release(terminalId: id!)
    }

    func testResolveLaunchFallsBackToZshWhenNotOnPath() {
        let launch = AcpTerminalHost.resolveLaunch(
            command: "definitely-not-a-real-binary-xyz",
            args: ["--flag"]
        )
        XCTAssertEqual(launch.exe, "/bin/zsh")
        XCTAssertEqual(launch.args.first, "-c")
        XCTAssertTrue(launch.args.last?.contains("definitely-not-a-real-binary-xyz") == true)
    }

    func testTruncateFromStartKeepsUtf8Boundary() {
        let text = "ééé" // each é is 2 bytes
        let data = Data(text.utf8)
        let trimmed = AcpTerminalHost.truncateFromStart(data, byteLimit: 3)
        XCTAssertTrue(trimmed.truncated)
        XCTAssertEqual(String(decoding: trimmed.data, as: UTF8.self), "é")
        XCTAssertLessThanOrEqual(trimmed.data.count, 3)
    }

    func testTruncateFromStartNoOpWhenUnderLimit() {
        let data = Data("hello".utf8)
        let trimmed = AcpTerminalHost.truncateFromStart(data, byteLimit: 100)
        XCTAssertFalse(trimmed.truncated)
        XCTAssertEqual(trimmed.data, data)
    }

    func testExitStatusAndWaitResponseShapes() {
        let ok = AcpTerminalHost.exitStatusJSON(reason: .exit, status: 0)
        XCTAssertEqual(ok["exitCode"] as? Int, 0)
        XCTAssertTrue(ok["signal"] is NSNull)
        let wait = AcpTerminalHost.waitResponse(from: ok)
        XCTAssertEqual(wait["exitCode"] as? Int, 0)
        XCTAssertTrue(wait["signal"] is NSNull)

        let killed = AcpTerminalHost.exitStatusJSON(reason: .uncaughtSignal, status: 15)
        XCTAssertTrue(killed["exitCode"] is NSNull)
        XCTAssertEqual(killed["signal"] as? String, "SIGTERM")
    }

    func testCreateEchoReturnsTerminalIdAndOutput() {
        let host = AcpTerminalHost()
        defer { host.releaseAll() }
        let created = try! host.create(
            params: ["command": "/bin/echo", "args": ["hello-acp-terminal"]],
            defaultCwd: FileManager.default.temporaryDirectory
        )
        let id = created["terminalId"] as? String
        XCTAssertNotNil(id)
        XCTAssertTrue(id?.hasPrefix("term_") == true)

        let exited = expectation(description: "echo exits")
        switch try! host.waitForExit(terminalId: id!) { payload in
            XCTAssertEqual(payload["exitCode"] as? Int, 0)
            exited.fulfill()
        } {
        case .alreadyExited(let payload):
            XCTAssertEqual(payload["exitCode"] as? Int, 0)
            exited.fulfill()
        case .pending:
            break
        }
        wait(for: [exited], timeout: 3)

        let snapshot = try! host.output(terminalId: id!)
        XCTAssertTrue((snapshot["output"] as? String)?.contains("hello-acp-terminal") == true)
        XCTAssertEqual(snapshot["truncated"] as? Bool, false)
        XCTAssertEqual((snapshot["exitStatus"] as? [String: Any])?["exitCode"] as? Int, 0)
        _ = try? host.release(terminalId: id!)
        XCTAssertThrowsError(try host.output(terminalId: id!)) { error in
            XCTAssertEqual(error as? AcpTerminalError, .unknownTerminal)
        }
    }

    func testUnknownTerminalErrors() {
        let host = AcpTerminalHost()
        XCTAssertThrowsError(try host.output(terminalId: "missing")) { error in
            XCTAssertEqual((error as? AcpTerminalError)?.jsonRPC["code"] as? Int, -32602)
            XCTAssertEqual((error as? AcpTerminalError)?.jsonRPC["message"] as? String, "Unknown terminalId")
        }
        XCTAssertEqual(
            AcpTerminalError.missingTerminalId.jsonRPC["message"] as? String,
            "terminal request requires terminalId"
        )
    }

    func testExitStatusFromFinishedProcessUsesRealCode() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["done"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try! process.run()
        process.waitUntilExit()
        let status = AcpTerminalHost.exitStatus(from: process)
        XCTAssertEqual(status["exitCode"] as? Int, 0)
        XCTAssertTrue(status["signal"] is NSNull)
    }
}
