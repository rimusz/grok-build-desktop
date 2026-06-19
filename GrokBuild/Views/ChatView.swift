import SwiftUI
import AppKit

struct ChatView: View {
    @Bindable var store: ChatStore

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let authMsg = store.authRequiredMessage {
                AuthBanner(
                    message: authMsg,
                    onDismiss: { store.authRequiredMessage = nil },
                    onRetry: { Task { await store.retryConnection() } }
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(store.messages) { msg in
                            MessageBubble(message: msg) { m in
                                // Preview is driven from ContentView via observed messages
                            }
                            .id(msg.id)
                        }

                        if store.isStreaming {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Streaming…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 6)
                            .transition(.opacity)
                        }

                        // Permission cards from ACP
                        ForEach(store.pendingPermissions) { perm in
                            PermissionCard(permission: perm) { optionId in
                                store.respondToPermission(perm, with: optionId)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            inputBar
        }
        .onAppear { inputFocused = true }
        .onChange(of: store.connectionState) { _, newState in
            if case .ready = newState {
                // Clear stale auth message if the CLI became ready again
                if store.authRequiredMessage != nil {
                    store.authRequiredMessage = nil
                }
            } else if case .failed(let msg) = newState,
                      (msg.lowercased().contains("login") || msg.lowercased().contains("auth")),
                      store.authRequiredMessage == nil {
                store.authRequiredMessage = msg
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chat")
                    .font(.title3.weight(.semibold))
                if let ws = store.currentWorkspace {
                    Text(ws.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            status
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(.bar)
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private var statusLabel: String {
        if store.authRequiredMessage != nil || store.process.needsAuthentication {
            return "Needs Login"
        }
        switch store.connectionState {
        case .idle: return "Idle"
        case .starting: return "Connecting"
        case .ready: return "Ready"
        case .busy: return "Working"
        case .failed: return "Error"
        }
    }

    private var statusColor: Color {
        if store.authRequiredMessage != nil || store.process.needsAuthentication {
            return .orange
        }
        switch store.connectionState {
        case .idle: return .gray
        case .starting: return .orange
        case .ready: return .green
        case .busy: return .blue
        case .failed: return .red
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            // Text input row
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Grok… (⌘↩ to send)", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .lineLimit(1...8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit {
                        // Plain return does newline (because axis vertical)
                    }
                    .onKeyPress { press in
                        if press.key == .return && press.modifiers.contains(.command) {
                            Task { await submit() }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        if let prev = store.previousHistory(from: input) {
                            input = prev
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if let next = store.nextHistory(from: input) {
                            input = next
                        }
                        return .handled
                    }

                if store.isStreaming {
                    // Stop generation button (replaces send button while generating)
                    Button {
                        store.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generation (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button {
                        Task { await submit() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              store.currentWorkspace == nil ||
                              store.authRequiredMessage != nil)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }

            // Mode + Model selectors at chat bottom (Cursor / VS Code style)
            HStack(spacing: 6) {
                modeSelector
                modelSelector
                Spacer()
            }
            .padding(.leading, 4)
        }
        .padding(12)
        .background(.bar)
    }

    private var modeSelector: some View {
        Menu {
            ForEach(store.availableModes, id: \.rawValue) { mode in
                let isSelected = store.currentMode == mode
                Button {
                    store.setMode(mode)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: iconName(for: mode))
                            .frame(width: 16, alignment: .center)
                        Text(displayName(for: mode))
                        Spacer(minLength: 12)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: iconName(for: store.currentMode))
                    .font(.caption.weight(.semibold))
                Text(displayName(for: store.currentMode))
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Change agent mode")
    }

    private var modelSelector: some View {
        Menu {
            ForEach(store.availableModels, id: \.self) { modelId in
                let isSelected = store.currentModel == modelId
                Button {
                    store.setModel(modelId)
                } label: {
                    HStack(spacing: 6) {
                        Text(store.modelDisplayName(modelId))
                        Spacer(minLength: 12)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.modelDisplayName(store.currentModel))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Select model (from grok models)")
    }

    private func displayName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "Plan"
        case "yolo": return "YOLO"
        default: return "Agent"
        }
    }

    private func iconName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "brain.head.profile"
        case "yolo": return "bolt.fill"
        default: return "infinity"
        }
    }

    private func helpText(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "Plan mode: outline changes first (read-only planning)"
        case "yolo": return "YOLO mode: auto-approve all tool calls and edits"
        default: return "Agent mode: normal interactive mode"
        }
    }

    private func submit() async {
        let text = input
        input = ""
        await store.send(text)
        inputFocused = true
    }
}

// MARK: - Auth Banner

struct AuthBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text("Authentication Required")
                    .font(.headline)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    openTerminalForLogin()
                } label: {
                    Label("Open Terminal & Run `grok login`", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copyLoginCommand()
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func openTerminalForLogin() {
        // Use AppleScript to open Terminal and run the login command
        let script = """
        tell application "Terminal"
            activate
            do script "grok login"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: just open Terminal
                openTerminalApp()
            }
        } else {
            openTerminalApp()
        }
    }

    private func openTerminalApp() {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(terminalURL)
    }

    private func copyLoginCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("grok login", forType: .string)
    }
}

// MARK: - Permission Card with Diff Preview

struct PermissionCard: View {
    let permission: PermissionRequest
    let onRespond: (String) -> Void

    @State private var showDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: permission.toolCall.isEdit ? "doc.text" : "terminal")
                Text(permission.toolCall.title)
                    .font(.headline)
                Spacer()
                Text(permission.toolCall.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let path = permission.toolCall.filePath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if permission.toolCall.isEdit, let content = permission.toolCall.proposedContent {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Proposed change:")
                            .font(.caption)
                        Button {
                            showDiff.toggle()
                            if showDiff {
                                // Deeper integration: open native diff using temp files
                                openNativeDiffPreview(permission.toolCall)
                            }
                        } label: {
                            Label("Preview Diff", systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                    ScrollView {
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .background(.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    if showDiff {
                        // Inline polished diff rendering (adapted from PreviewPane)
                        DiffLinesView(content: content)
                            .frame(maxHeight: 100)
                    }
                }
            } else if permission.toolCall.isExecute, let cmd = permission.toolCall.command {
                Text("Command: \(cmd)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                ForEach(permission.options) { option in
                    Button(option.name) {
                        onRespond(option.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(option.kind.contains("allow") ? .green : .red)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.yellow.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .transition(.scale.combined(with: .opacity)) // UI polish: animation
        .animation(.spring(response: 0.3), value: permission.id)
    }

    private func openNativeDiffPreview(_ toolCall: ToolCall) {
        guard let path = toolCall.filePath,
              let proposed = toolCall.proposedContent else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let oldURL = tempDir.appendingPathComponent("grok-old-\(UUID().uuidString).txt")
        let newURL = tempDir.appendingPathComponent("grok-new-\(UUID().uuidString).txt")

        do {
            // Try to get current content as "old"
            let oldContent = (try? String(contentsOfFile: path)) ?? ""
            try oldContent.write(to: oldURL, atomically: true, encoding: .utf8)
            try proposed.write(to: newURL, atomically: true, encoding: .utf8)

            // Deeper: use opendiff (FileMerge) or Xcode for native diff
            let process = Process()
            if FileManager.default.fileExists(atPath: "/usr/bin/opendiff") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
                process.arguments = [oldURL.path, newURL.path]
            } else {
                // Fallback to opening both or use VS Code if available
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Xcode", oldURL.path, newURL.path]
            }
            try process.run()
        } catch {
            // Silent fallback
            print("Failed to open native diff: \(error)")
        }
    }
}

// Simple inline diff lines for polish in permission card (reuses idea from DiffView)
struct DiffLinesView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(content.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let (text, color, bg) = diffStyle(for: line)
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .background(bg, in: Rectangle())
            }
        }
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    private func diffStyle(for line: String) -> (String, Color, Color) {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return (line, .green, .green.opacity(0.15))
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return (line, .red, .red.opacity(0.15))
        } else if line.hasPrefix("@@") {
            return (line, .blue, .blue.opacity(0.1))
        } else {
            return (line, .primary, .clear)
        }
    }
}

