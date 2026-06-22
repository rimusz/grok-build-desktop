import XCTest
@testable import GrokBuild

final class BrowserIntegrationTests: XCTestCase {
    private var savedEnabled: Any?
    private var savedBackend: Any?
    private var savedCDPURL: Any?
    private var savedProfileName: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedEnabled = defaults.object(forKey: BrowserSettingsKeys.enabled)
        savedBackend = defaults.object(forKey: BrowserSettingsKeys.backend)
        savedCDPURL = defaults.object(forKey: BrowserSettingsKeys.cdpURL)
        savedProfileName = defaults.object(forKey: BrowserSettingsKeys.profileName)
    }

    override func tearDown() {
        restore(savedEnabled, forKey: BrowserSettingsKeys.enabled)
        restore(savedBackend, forKey: BrowserSettingsKeys.backend)
        restore(savedCDPURL, forKey: BrowserSettingsKeys.cdpURL)
        restore(savedProfileName, forKey: BrowserSettingsKeys.profileName)
        super.tearDown()
    }

    func testBrowserSettingsRoundTrip() {
        let settings = BrowserSettings(
            enabled: true,
            backend: .agentBrowser,
            cdpURL: "http://127.0.0.1:9222",
            profileName: "project-a"
        )

        BrowserSettingsStore.save(settings)
        XCTAssertEqual(BrowserSettingsStore.load(), settings)
    }

    func testMCPServerConfigSerializesForACP() {
        let config = MCPServerConfig(
            name: "grokbuild-browser",
            command: "/tmp/grokbuild-browser-mcp",
            args: ["--stdio"],
            env: ["AGENT_BROWSER_PATH": "/opt/homebrew/bin/agent-browser"]
        )

        let json = config.jsonObject

        XCTAssertEqual(json["name"] as? String, "grokbuild-browser")
        XCTAssertEqual(json["type"] as? String, "stdio")
        XCTAssertEqual(json["transport"] as? String, "stdio")
        XCTAssertEqual(json["command"] as? String, "/tmp/grokbuild-browser-mcp")
        XCTAssertEqual(json["args"] as? [String], ["--stdio"])

        let env = json["env"] as? [[String: String]]
        XCTAssertEqual(env?.first?["name"], "AGENT_BROWSER_PATH")
        XCTAssertEqual(env?.first?["value"], "/opt/homebrew/bin/agent-browser")
    }

    func testAgentBrowserCommandPreviewKeepsArguments() {
        let command = AgentBrowserService.commandPreview(["open", "https://example.com"])

        XCTAssertGreaterThanOrEqual(command.count, 3)
        XCTAssertEqual(Array(command.suffix(2)), ["open", "https://example.com"])
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

