import AppKit

final class InputVolumeMenuView: NSView {
    private let percentageLabel = NSTextField(labelWithString: "")
    private let onChange: (Float) -> Bool

    init(volume: Float, onChange: @escaping (Float) -> Bool) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 286, height: 38))

        let iconView = NSImageView(frame: NSRect(x: 14, y: 11, width: 16, height: 16))
        iconView.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: L10n.inputVolume
        )
        iconView.contentTintColor = .secondaryLabelColor
        addSubview(iconView)

        let slider = NSSlider(
            value: Double(volume),
            minValue: 0,
            maxValue: 1,
            target: self,
            action: #selector(volumeChanged(_:))
        )
        slider.frame = NSRect(x: 42, y: 8, width: 185, height: 22)
        slider.isContinuous = true
        slider.toolTip = L10n.inputVolume
        slider.setAccessibilityLabel(L10n.inputVolume)
        addSubview(slider)

        percentageLabel.frame = NSRect(x: 235, y: 10, width: 40, height: 18)
        percentageLabel.alignment = .right
        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentageLabel.textColor = .secondaryLabelColor
        addSubview(percentageLabel)

        updatePercentage(volume)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func volumeChanged(_ slider: NSSlider) {
        let value = Float(slider.doubleValue)
        updatePercentage(value)
        let didApply = onChange(value)
        percentageLabel.textColor = didApply ? .secondaryLabelColor : .systemRed
        percentageLabel.toolTip = didApply ? nil : L10n.volumeFailed
    }

    private func updatePercentage(_ volume: Float) {
        percentageLabel.stringValue = "\(Int((volume * 100).rounded()))%"
    }
}
