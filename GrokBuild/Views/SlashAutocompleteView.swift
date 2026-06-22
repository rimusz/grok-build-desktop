import SwiftUI

// MARK: - Slash autocomplete

private struct SlashDisplayRow: Identifiable {
    enum Kind {
        case header(String)
        case divider
        case command(SlashCommand)
        case showMoreSkills(count: Int)
        case showMoreCommands(count: Int)
    }

    let id: String
    let kind: Kind
    let navigableIndex: Int?
}

struct SlashAutocompleteView: View {
    let entries: [SlashMenuEntry]
    let activeIndex: Int
    var onSelect: (SlashCommand) -> Void
    var onShowMoreSkills: () -> Void
    var onShowMoreCommands: () -> Void

    private var rows: [SlashDisplayRow] {
        var result: [SlashDisplayRow] = []
        var skillsHeaderAdded = false
        var commandsHeaderAdded = false

        for (index, entry) in entries.enumerated() {
            switch entry {
            case .command(let command):
                if command.isSkill {
                    if !skillsHeaderAdded {
                        result.append(.init(id: "header-skills", kind: .header("Skills"), navigableIndex: nil))
                        skillsHeaderAdded = true
                    }
                } else if !commandsHeaderAdded {
                    if skillsHeaderAdded {
                        result.append(.init(id: "divider", kind: .divider, navigableIndex: nil))
                    }
                    result.append(.init(id: "header-commands", kind: .header("Commands"), navigableIndex: nil))
                    commandsHeaderAdded = true
                }
                result.append(.init(id: "cmd-\(command.id)-\(index)", kind: .command(command), navigableIndex: index))

            case .showMoreSkills(let count):
                if !skillsHeaderAdded {
                    result.append(.init(id: "header-skills", kind: .header("Skills"), navigableIndex: nil))
                    skillsHeaderAdded = true
                }
                result.append(.init(id: "more-skills", kind: .showMoreSkills(count: count), navigableIndex: index))

            case .showMoreCommands(let count):
                if !commandsHeaderAdded {
                    if skillsHeaderAdded {
                        result.append(.init(id: "divider", kind: .divider, navigableIndex: nil))
                    }
                    result.append(.init(id: "header-commands", kind: .header("Commands"), navigableIndex: nil))
                    commandsHeaderAdded = true
                }
                result.append(.init(id: "more-commands", kind: .showMoreCommands(count: count), navigableIndex: index))
            }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        Group {
                            switch row.kind {
                            case .header(let title):
                                sectionHeader(title)
                            case .divider:
                                Divider().padding(.vertical, 6)
                            case .command(let command):
                                slashRow(command, isActive: row.navigableIndex == activeIndex)
                            case .showMoreSkills(let count):
                                showMoreRow(
                                    count: count,
                                    isActive: row.navigableIndex == activeIndex,
                                    action: onShowMoreSkills
                                )
                            case .showMoreCommands(let count):
                                showMoreRow(
                                    count: count,
                                    isActive: row.navigableIndex == activeIndex,
                                    action: onShowMoreCommands
                                )
                            }
                        }
                        .id(row.navigableIndex.map { "slash-nav-\($0)" })
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: activeIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("slash-nav-\(newIndex)", anchor: .center)
                }
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 360)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    private func slashRow(_ command: SlashCommand, isActive: Bool) -> some View {
        Button {
            onSelect(command)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("/\(command.name)")
                    .font(.body)
                    .foregroundStyle(.primary)
                if !command.description.isEmpty {
                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showMoreRow(count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Show \(count) more")
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum SlashAutocomplete {
    static func match(in text: String) -> (query: String, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\n)/(\S*)$"#) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let result = regex.firstMatch(in: text, range: range),
              result.numberOfRanges > 1 else { return nil }
        let fullRange = Range(result.range, in: text)!
        let queryRange = Range(result.range(at: 1), in: text)!
        return (String(text[queryRange]), fullRange)
    }

    static func apply(command: SlashCommand, to text: String, matchRange: Range<String.Index>) -> String {
        let prefix = text[matchRange.lowerBound].isNewline ? "\n" : ""
        let replacement = "\(prefix)/\(command.name) "
        return text.replacingCharacters(in: matchRange, with: replacement)
    }
}
