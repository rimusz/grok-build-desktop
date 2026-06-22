import Foundation

struct MCPServerConfig: Sendable, Equatable {
    enum Transport: String, Sendable {
        case stdio
        case http
        case sse
    }

    var name: String
    var transport: Transport
    var command: String?
    var args: [String]
    var url: String?
    var env: [String: String]

    init(
        name: String,
        transport: Transport = .stdio,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        env: [String: String] = [:]
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.env = env
    }

    var jsonObject: [String: Any] {
        switch transport {
        case .stdio:
            return [
                "name": name,
                "command": command ?? "",
                "args": args,
                "env": env.map { key, value in ["name": key, "value": value] }
            ]
        case .http, .sse:
            return [
                "name": name,
                "type": transport.rawValue,
                "url": url ?? "",
                "headers": []
            ]
        }
    }
}

