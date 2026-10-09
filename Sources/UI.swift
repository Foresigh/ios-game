import UIKit

/// Shared look for the app's UIKit screens (menu and TV remote).
enum Palette {
    static let background = UIColor(red: 0.06, green: 0.10, blue: 0.14, alpha: 1)
    static let accent = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1)
    static let accentText = UIColor(red: 0.02, green: 0.07, blue: 0.10, alpha: 1)
    static let secondary = UIColor(white: 1, alpha: 0.10)
    static let text = UIColor.white
    static let dimText = UIColor(white: 1, alpha: 0.6)
    static let error = UIColor(red: 1.0, green: 0.45, blue: 0.42, alpha: 1)
}

/// A rounded button that runs a closure (iOS 12 has no UIAction).
final class ActionButton: UIButton {
    enum Style { case primary, secondary }

    private var handler: (() -> Void)?

    convenience init(_ title: String, style: Style = .secondary, fontSize: CGFloat = 20, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.handler = handler
        setTitle(title, for: .normal)
        titleLabel?.font = UIFont.boldSystemFont(ofSize: fontSize)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.6
        setTitleColor(style == .primary ? Palette.accentText : Palette.text, for: .normal)
        backgroundColor = style == .primary ? Palette.accent : Palette.secondary
        layer.cornerRadius = 14
        contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    @objc private func tapped() { handler?() }
}

extension UILabel {
    convenience init(text: String, size: CGFloat, bold: Bool = false, color: UIColor = Palette.text) {
        self.init(frame: .zero)
        self.text = text
        font = bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        textColor = color
        numberOfLines = 0
        textAlignment = .center
    }
}

extension UIStackView {
    convenience init(_ views: [UIView], axis: NSLayoutConstraint.Axis, spacing: CGFloat,
                     distribution: UIStackView.Distribution = .fill) {
        self.init(arrangedSubviews: views)
        self.axis = axis
        self.spacing = spacing
        self.distribution = distribution
    }
}
