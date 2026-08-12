import Foundation
import UniformTypeIdentifiers

/// A pasted or dropped image queued for the next prompt as vision/multimodal content
/// (an ACP `image` content block), distinct from path-based file attachments.
struct ImageAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let mimeType: String
    let data: Data

    init(id: UUID = UUID(), displayName: String, mimeType: String, data: Data) {
        self.id = id
        self.displayName = displayName
        self.mimeType = mimeType
        self.data = data
    }

    var base64: String { data.base64EncodedString() }
}

/// Detects image content for vision attachments and maps extensions/UTTypes to MIME types.
enum ImageAttachmentSupport {
    /// Image extensions attached as vision content (grok multimodal input).
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    static func isImagePath(_ path: String) -> Bool {
        supportedExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    static func mimeType(forPath path: String) -> String? {
        mimeType(forExtension: (path as NSString).pathExtension)
    }

    /// True when the pasteboard/drag type identifier conforms to a supported image type.
    static func isImageTypeIdentifier(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .image)
    }

    static func displayName(forPath path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
