import AppKit

/// Transient message shown near the bottom of the canvas area; fades out on its own.
final class ToastView: NSView {
    private let host = GlassHost(cornerRadius: 12, shadow: true, veil: Theme.cardVeil)
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideTimer: Timer?

    init() {
        super.init(frame: .zero)
        alphaValue = 0
        isHidden = true
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        host.content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.content.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: host.content.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: host.content.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: host.content.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        host.frame = bounds
    }

    var text: String { label.stringValue }

    /// Preferred size for `text` given a maximum width.
    func size(for text: String, maxWidth: CGFloat) -> CGSize {
        label.stringValue = text
        label.preferredMaxLayoutWidth = maxWidth - 36
        let s = label.intrinsicContentSize
        return CGSize(width: min(maxWidth, s.width + 36), height: s.height + 20)
    }

    func show(_ text: String, duration: TimeInterval = 4) {
        label.stringValue = text
        hideTimer?.invalidate()
        isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in self?.dismiss() }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.alphaValue == 0 { self?.isHidden = true }
        })
    }
}
