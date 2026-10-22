import UIKit

/// A label with a coloured capsule behind it, used for badges.
final class PillLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8) {
        didSet { invalidateIntrinsicContentSize() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        textAlignment = .center
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = super.sizeThatFits(CGSize(
            width: max(size.width - contentInsets.left - contentInsets.right, 0),
            height: max(size.height - contentInsets.top - contentInsets.bottom, 0)
        ))
        return CGSize(width: inner.width + contentInsets.left + contentInsets.right, height: inner.height + contentInsets.top + contentInsets.bottom)
    }

    override var intrinsicContentSize: CGSize {
        sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    }
}
