import AppKit

/// Floating vertical slider card shown at the left of the canvas (brush Size and Opacity).
final class VerticalSliderView: NSView {
    private let host = GlassHost(cornerRadius: 10, material: .blur, shadow: true, veil: Theme.cardVeil)
    private let icon = NSImageView()
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    private var updating = false
    var onChange: ((Double) -> Void)?
    let formatter: (Double) -> String

    init(symbol: String, tooltip: String, min: Double, max: Double, formatter: @escaping (Double) -> String) {
        self.formatter = formatter
        super.init(frame: .zero)
        toolTip = tooltip
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        icon.image = Theme.symbol(symbol, size: 13)?.tinted(Theme.text)
        icon.imageScaling = .scaleProportionallyDown
        host.content.addSubview(icon)
        slider.minValue = min
        slider.maxValue = max
        slider.isVertical = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(changed)
        host.content.addSubview(slider)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        valueLabel.textColor = Theme.text
        valueLabel.alignment = .center
        host.content.addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        host.frame = bounds
        let w = bounds.width
        icon.frame = CGRect(x: (w - 16) / 2, y: 8, width: 16, height: 16)
        valueLabel.frame = CGRect(x: 0, y: bounds.height - 18, width: w, height: 14)
        slider.frame = CGRect(x: (w - 20) / 2, y: 30, width: 20, height: bounds.height - 52)
    }

    var value: Double {
        get { slider.doubleValue }
        set {
            updating = true
            slider.doubleValue = newValue
            valueLabel.stringValue = formatter(newValue)
            updating = false
        }
    }

    @objc private func changed() {
        valueLabel.stringValue = formatter(slider.doubleValue)
        guard !updating else { return }
        onChange?(slider.doubleValue)
    }
}
