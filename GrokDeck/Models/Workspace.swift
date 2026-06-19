import Foundation

struct Workspace: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var name: String
    var path: URL

    var displayName: String {
        name.isEmpty ? path.lastPathComponent : name
    }

    init(id: UUID = UUID(), name: String = "", path: URL) {
        self.id = id
        self.name = name
        self.path = path
    }
}
