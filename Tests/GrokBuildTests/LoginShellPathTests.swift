import XCTest
@testable import GrokBuild

final class LoginShellPathTests: XCTestCase {
    func testMergePutsShellEntriesFirstAndDropsDuplicates() {
        let merged = LoginShellPath.merge(
            "/opt/homebrew/bin:/usr/bin:/bin",
            with: "/usr/bin:/bin:/usr/sbin:/sbin:/opt/custom/bin"
        )
        XCTAssertEqual(
            merged,
            "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/custom/bin"
        )
    }

    func testExtractMarkedPathIgnoresProfileNoise() {
        let output = """
        Last login: Tue
        \(LoginShellPath.markerStart)/opt/homebrew/bin:/usr/bin\(LoginShellPath.markerEnd)
        extra
        """
        XCTAssertEqual(
            LoginShellPath.extractMarkedPath(from: output),
            "/opt/homebrew/bin:/usr/bin"
        )
        XCTAssertNil(LoginShellPath.extractMarkedPath(from: "no markers here"))
        XCTAssertNil(LoginShellPath.extractMarkedPath(from: "\(LoginShellPath.markerStart)\(LoginShellPath.markerEnd)"))
    }

    func testLoginShellPrefersPasswdThenSHELL() {
        XCTAssertEqual(
            LoginShellPath.loginShell(passwdShell: "/bin/zsh", environment: ["SHELL": "/bin/bash"]),
            "/bin/zsh"
        )
        XCTAssertEqual(
            LoginShellPath.loginShell(passwdShell: nil, environment: ["SHELL": "/opt/homebrew/bin/fish"]),
            "/opt/homebrew/bin/fish"
        )
        XCTAssertEqual(
            LoginShellPath.loginShell(passwdShell: "  ", environment: [:]),
            "/bin/zsh"
        )
    }

    func testShellInvocationUsesLoginInteractiveExceptCsh() {
        XCTAssertEqual(
            LoginShellPath.shellInvocation(shell: "/bin/zsh", command: "echo hi"),
            ["-i", "-l", "-c", "echo hi"]
        )
        XCTAssertEqual(
            LoginShellPath.shellInvocation(shell: "/bin/csh", command: "echo hi"),
            ["-c", "echo hi"]
        )
    }

    func testApplySkipsWhenEnvVarSet() {
        var set: String?
        let status = LoginShellPath.apply(
            environment: [
                LoginShellPath.skipEnvVar: "1",
                "PATH": "/usr/bin"
            ],
            passwdShell: "/bin/zsh",
            resolve: { _, _ in XCTFail("should not resolve"); return nil },
            setPATH: { set = $0 }
        )
        XCTAssertEqual(status, .skipped(reason: LoginShellPath.skipEnvVar))
        XCTAssertNil(set)
        XCTAssertEqual(LoginShellPath.lastStatus, status)
        XCTAssertTrue(status.doctorDetail.contains(LoginShellPath.skipEnvVar))
        XCTAssertEqual(status.doctorStatus, .info)
    }

    func testApplyMergesResolvedShellPath() {
        var set: String?
        let status = LoginShellPath.apply(
            environment: ["PATH": "/usr/bin:/bin"],
            passwdShell: "/bin/zsh",
            resolve: { shell, _ in
                XCTAssertEqual(shell, "/bin/zsh")
                return "/opt/homebrew/bin:/usr/bin"
            },
            setPATH: { set = $0 }
        )
        XCTAssertEqual(set, "/opt/homebrew/bin:/usr/bin:/bin")
        if case .applied(let shell, let count) = status {
            XCTAssertEqual(shell, "/bin/zsh")
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("expected applied, got \(status)")
        }
        XCTAssertEqual(status.doctorStatus, .ok)
        XCTAssertTrue(status.doctorDetail.contains("3 entries"))
        XCTAssertFalse(status.doctorDetail.contains("/opt/homebrew"))
    }

    func testApplyFallsBackWhenUserShellFails() {
        var resolved: [String] = []
        let status = LoginShellPath.apply(
            environment: ["PATH": "/usr/bin"],
            passwdShell: "/opt/homebrew/bin/fish",
            resolve: { shell, _ in
                resolved.append(shell)
                return shell == "/bin/zsh" ? "/opt/homebrew/bin" : nil
            },
            setPATH: { _ in }
        )
        XCTAssertEqual(resolved, ["/opt/homebrew/bin/fish", "/bin/zsh"])
        if case .applied(let shell, _) = status {
            XCTAssertEqual(shell, "/bin/zsh")
        } else {
            XCTFail("expected fallback apply, got \(status)")
        }
    }

    func testApplyFailedWhenNoShellPATH() {
        let status = LoginShellPath.apply(
            environment: ["PATH": "/usr/bin"],
            passwdShell: "/bin/zsh",
            resolve: { _, _ in nil },
            setPATH: { _ in XCTFail("should not set PATH") }
        )
        XCTAssertEqual(status, .failed(shell: "/bin/zsh"))
        XCTAssertEqual(status.doctorStatus, .warning)
        XCTAssertTrue(status.doctorDetail.contains("launchd PATH"))
    }

    func testInheritedEnvironmentWritesCurrentPATH() {
        let env = LoginShellPath.inheritedEnvironment(["FOO": "bar", "PATH": "/usr/bin"])
        XCTAssertEqual(env["FOO"], "bar")
        XCTAssertFalse(env["PATH"]?.isEmpty ?? true)
    }
}
