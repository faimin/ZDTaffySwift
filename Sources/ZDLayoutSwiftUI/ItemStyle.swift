#if canImport(SwiftUI)
import SwiftUI
import ZDLayoutCore

/// The layout properties of one child of a ``FlexLayout``. Set them with ``SwiftUI/View/flexItem(_:)``.
///
/// It mirrors the per-item part of ``LayoutStyle``; container-level properties (axis, gap, alignment, tracks)
/// belong to the layout itself.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
public struct ItemStyle: Sendable {
    public var grow: CGFloat = 0
    public var shrink: CGFloat = 0
    public var basis: Length = .auto
    public var width: Length = .auto
    public var height: Length = .auto
    public var minWidth: Length = .auto
    public var minHeight: Length = .auto
    public var maxWidth: Length = .auto
    public var maxHeight: Length = .auto
    public var aspectRatio: CGFloat?
    public var alignSelf: ItemAlignment?
    public var margin: Edges = .zero
    /// Takes no space and is not placed.
    public var isHidden = false
    public var gridColumn: GridItemPlacement = .auto
    public var gridRow: GridItemPlacement = .auto

    public init() {}

    func apply(to style: inout LayoutStyle) {
        style.grow = grow
        style.shrink = shrink
        style.basis = basis
        style.width = width
        style.height = height
        style.minWidth = minWidth
        style.minHeight = minHeight
        style.maxWidth = maxWidth
        style.maxHeight = maxHeight
        style.aspectRatio = aspectRatio
        style.alignSelf = alignSelf
        style.margin = margin
        style.isHidden = isHidden
        style.gridColumn = gridColumn
        style.gridRow = gridRow
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
struct ItemStyleKey: LayoutValueKey {
    static let defaultValue = ItemStyle()
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension View {
    /// Sets how this view takes part in an enclosing ``FlexLayout`` / ``FlexStack``.
    ///
    /// ```swift
    /// FlexStack(.row, gap: 8) {
    ///     Image(systemName: "star").flexItem { $0.shrink = 0 }
    ///     Text("A long title").flexItem { $0.grow = 1; $0.shrink = 1 }
    /// }
    /// ```
    public func flexItem(_ configure: (inout ItemStyle) -> Void) -> some View {
        var style = ItemStyle()
        configure(&style)
        return layoutValue(key: ItemStyleKey.self, value: style)
    }

    /// Shorthand for the properties used most often.
    public func flexItem(
        grow: CGFloat = 0,
        shrink: CGFloat = 0,
        basis: Length = .auto,
        alignSelf: ItemAlignment? = nil,
        margin: Edges = .zero
    ) -> some View {
        flexItem {
            $0.grow = grow
            $0.shrink = shrink
            $0.basis = basis
            $0.alignSelf = alignSelf
            $0.margin = margin
        }
    }

    /// Places this view in a grid track range (1-based lines, negative from the end) of a ``FlexLayout`` grid.
    public func gridItem(column: GridItemPlacement = .auto, row: GridItemPlacement = .auto) -> some View {
        flexItem {
            $0.gridColumn = column
            $0.gridRow = row
        }
    }
}
#endif
