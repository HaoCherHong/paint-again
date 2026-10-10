import AppKit

/// Full-window overlay listing every entry of `Shortcuts.sections` in columns on a frosted card. A click
/// anywhere dismisses it.
final class ShortcutCheatSheetView: NSView {
    var onDismiss: (() -> Void)?

    private let card = GlassHost(cornerRadius: 14, material: .blur, shadow: true, veil: Theme.cardVeil)
    private let columns = NSStackView()
    private static let columnCount = 4
    private static let padding: CGFloat = 24

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(card)
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 28
        columns.translatesAutoresizingMaskIntoConstraints = false
        card.content.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo: card.content.topAnchor, constant: Self.padding),
            columns.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: Self.padding),
        ])
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func rightMouseDown(with event: NSEvent) { onDismiss?() }

    /// Splits the sections into columns of similar height, keeping their order.
    private func build() {
        let sections = Shortcuts.sections
        func weight(_ s: ShortcutSection) -> Int { s.items.count + 2 }
        let target = Double(sections.map(weight).reduce(0, +)) / Double(Self.columnCount)
        var groups: [[ShortcutSection]] = [[]]
        var filled = 0
        for section in sections {
            if filled > 0, Double(filled + weight(section) / 2) > target, groups.count < Self.columnCount {
                groups.append([])
                filled = 0
            }
            groups[groups.count - 1].append(section)
            filled += weight(section)
        }
        for group in groups {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 18
            column.setHuggingPriority(.required, for: .vertical)
            for section in group { column.addArrangedSubview(sectionView(section)) }
            columns.addArrangedSubview(column)
        }
    }

    private func sectionView(_ section: ShortcutSection) -> NSView {
        let header = NSTextField(labelWithString: section.title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = Theme.text
        let rows: [[NSView]] = section.items.map { item in
            let keys = NSTextField(labelWithString: item.display)
            keys.font = .systemFont(ofSize: 12)
            keys.textColor = .secondaryLabelColor
            keys.alignment = .right
            let title = NSTextField(labelWithString: item.title)
            title.font = .systemFont(ofSize: 12)
            title.textColor = Theme.text
            return [keys, title]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 5
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.setContentHuggingPriority(.required, for: .vertical)
        let stack = NSStackView(views: [header, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setHuggingPriority(.required, for: .vertical)
        return stack
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let content = columns.fittingSize
        let size = CGSize(width: min(bounds.width - 32, content.width + Self.padding * 2),
                          height: min(bounds.height - 32, content.height + Self.padding * 2))
        card.frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                            width: size.width, height: size.height).integral
    }
}
