# ZDTaffy

[English](README.md) · [中文](README.zh-CN.md)

Swift bindings for [Taffy](https://github.com/DioxusLabs/taffy) (CSS Block, Flexbox and Grid layout in Rust) on Apple platforms, generated with [BoltFFI](https://github.com/boltffi/boltffi).

- Taffy `0.15.0`, BoltFFI `0.31.1`
- iOS 15+, macOS 13+ (device and simulator slices, `arm64` and `x86_64`)
- Complete `Style`: Block, Flexbox and Grid properties (`calc()` is not exposed)
- Leaf measurement via a `Measure` protocol, a closure, or an `async` closure

## Usage

```swift
import ZDTaffy

let tree = TaffyTree()

var item = Style()
item.flexGrow = 1
let a = try tree.newLeaf(style: item)
let b = try tree.newLeaf(style: item)

var container = Style()
container.display = .flex
container.size = DimensionSize(width: .length(200), height: .length(100))
let root = try tree.newWithChildren(style: container, children: [a, b])

try tree.computeLayout(root: root, available: .maxContent)
let layout = try tree.layout(node: b)   // location (100, 0), size (100, 100)
```

Measuring content (text, images) — the closure runs synchronously while layout is computed:

```swift
try tree.computeLayout(root: root, available: .definite(width: 320, height: 480)) { node, known, available in
    // Return the content size of the leaf `node`.
    Size(width: 40, height: 12)
}
```

`known` holds dimensions the parent algorithm has already fixed (e.g. a stretched cross axis). A size from the node's own style arrives as `.definite` in `available`.

When measuring has to suspend (for example text measured on the main actor), use the async variant:

```swift
try await tree.computeLayoutAsync(root: root, available: .maxContent) { node, known, available in
    await MainActor.run { measureText(for: node, in: available.width) }
}
```

The layout algorithm itself is synchronous, so it is re-run until a pass needs no new measurements. The closure may therefore be asked about sizes that end up unused and must return the same answer for the same input; if the answers never settle, `TaffyError.measureDidNotConverge` is thrown.

Naming notes: Taffy's `Dimension`, `Layout` and `Float` are exposed as `TaffyDimension`, `NodeLayout` and `FloatSide` to avoid clashing with Foundation, SwiftUI and the Swift standard library. Generic Taffy types (`Size<T>`, `Rect<T>`, …) become concrete types such as `DimensionSize` and `LengthPercentageRect`.

## Behaviour worth knowing

- `TaffyTree` is thread-safe (calls are serialized by a lock). Do **not** call the same tree from inside a `Measure` callback; it would deadlock.
- Stale or foreign `NodeId`s throw `TaffyError` instead of crashing, and links that would create a cycle are rejected.
- The generated bindings are compiled in Swift 5 language mode: BoltFFI keeps callback tables in global `var`s that Swift 6 strict concurrency rejects. Apps using Swift 6 are unaffected.

## Building

Requires Xcode 16+, Rust (stable) with the Apple targets and the BoltFFI CLI:

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin
cargo install boltffi_cli --version 0.31.1

./scripts/build-xcframework.sh   # builds Artifacts/ZDTaffy.xcframework and refreshes the generated Swift
swift test
```

`Artifacts/` is git-ignored; the generated Swift (`Sources/ZDTaffy/Generated`) and C shim (`Sources/ZDTaffyFFI`) are committed. Layout of the repo:

| Path | Contents |
|---|---|
| `rust/` | Rust crate wrapping Taffy, annotated for BoltFFI |
| `Sources/ZDTaffy/` | Hand-written Swift conveniences + generated bindings |
| `Tests/ZDTaffyTests/` | Swift Testing suites |
| `scripts/` | XCFramework build script |

## ZDLayout (in progress)

`ZDLayout` is a declarative layout framework for UIKit built on top of `ZDTaffy`. This section records the agreed design and the trade-offs behind it.

**Status:** `ZDLayoutCore` (node tree, containers, modifiers, solver, pixel snapping) is implemented and tested. The UIKit layer (`ZDLayout`: `FlexView`, `FlexScrollView`, `UIView` leaves, cells) is still design only, so the UIKit-facing snippets below are a sketch and may change.

### Goals

- Describe layout and view hierarchy in one place — no manual `addSubview` / `addChildren` / `markDirty`.
- Strongly typed values instead of `YGValue`.
- Participate in UIKit's own layout cycle (`layoutSubviews`, Auto Layout, self-sizing cells) instead of running beside it.
- Flexbox, Block **and CSS Grid**, powered by Taffy.

### Modules

| Target | Depends on | Contents |
|---|---|---|
| `ZDLayoutCore` | `ZDTaffy` | Platform-agnostic: node tree, `Style` builders, solver, measure protocol. No UIKit, so `swift test` on macOS covers it. |
| `ZDLayout` | `ZDLayoutCore`, UIKit | `FlexView`, `FlexScrollView`, DSL, `UIView` adapters, `FlexContentConfiguration`. |

Requirements: Swift 6 language mode, iOS 15+. Everything UIKit-facing is `@MainActor`.

### Usage sketch

```swift
import ZDLayout

final class ProfileHeader: FlexView {
    let avatar = UIImageView()
    let name = UILabel()
    let badge = BadgeView()

    init() {
        super.init {
            Row(gap: 12, alignItems: .center) {
                avatar.width(40).height(40)
                Column(gap: 4) {
                    name
                    Row {
                        Spacer()
                        badge
                    }
                }
                .grow(1)
            }
            .padding(16)
        }
    }
}
```

- **Containers**: `Row`, `Column`, `Flex(direction:wrap:)`, `Grid`, plus `Spacer`. There is no `ZStack`; make a child overlap with `.absolute(inset:)`.
- **Leaves**: any `UIView` you own can be placed in the builder directly. A few thin wrappers (`Label("text")`, …) create the view for you.
- **Modifiers** (`.width`, `.height`, `.size`, `.grow`, `.shrink`, `.basis`, `.margin`, `.padding`, `.absolute(inset:)`, `.gridColumn(_:span:)`, `.hidden()`, `.styled { }`, …) all edit one value type, `Style`, which mirrors `ZDTaffy.Style`. `.styled { $0.… }` edits the full `LayoutStyle`, and `.custom { $0.… }` reaches the underlying `ZDTaffy.Style`, so nothing Taffy can do is out of reach.
- **Values**: numbers are points (`.width(100)`); percentages are `.percent(50)` or `50.percent`. There is deliberately no `50%` operator. Public API uses `CGFloat`; the conversion to Taffy's `Float` is internal.

```swift
Grid(columns: [.fixed(80), .fr(1), .fr(2)], rows: [.auto], gap: 8) {
    icon
    title.gridColumn(2, span: 2)
}
```

Grid exposes tracks (`.fixed`, `.fr`, `.auto`, `.minmax`, `.repeat`), `gap`, `autoFlow` and item placement by line / span. Named areas and named lines are not part of the DSL; use `.custom { $0.gridTemplateAreas = … }`.

### How layout is triggered (and what you must do)

`FlexView` is a `UIView` that solves in `layoutSubviews` and implements `sizeThatFits(_:)` / `intrinsicContentSize`, so it works inside Auto Layout, `UIStackView` and self-sizing cells, and inside `UIView.animate { view.layoutIfNeeded() }`.

**You trigger layout the UIKit way: call `setNeedsLayout()`** (or `invalidateIntrinsicContentSize()` when the size the view reports changes). There is no `markDirty` and no private RunLoop observer; UIKit coalesces the requests itself.

### Trade-off: leaf measurement is never cached across passes

UIKit does not tell a parent when a `UILabel`'s text changes. Two designs were possible:

| | Behaviour | Cost |
|---|---|---|
| **Chosen: re-measure every pass** | Each layout pass calls `sizeThatFits` on every leaf. Whatever is true *now* is what gets laid out. | A few dozen `sizeThatFits` calls per pass. |
| Explicit invalidation (what ZDFlexLayoutKit does) | Leaf sizes are cached until you call `markDirty`. | Forgetting `markDirty` silently shows a stale layout. This was the most common bug in the old library. |

Consequences:

- After changing a label's text, font or image, call `flexView.setNeedsLayout()` (UIKit already requires this for frame-based layout). You never need to know *which* node changed.
- Large screens with hundreds of leaves pay for hundreds of measurements per pass. If profiling shows this matters, an opt-in cache keyed by `(view, size constraint)` can be added; it is intentionally not the default because a cache that can go stale is worse than a slow one.
- Measurement within a single pass is memoised, so one leaf asked the same question twice by the solver is only measured once.
- `Measure` must be a pure function of the view's current state and the constraint.

### Trade-off: UIKit environment semantics are automatic

| Concern | Behaviour | Why / what to know |
|---|---|---|
| **Hidden views** | A view with `isHidden == true` is treated as `display: none` and takes no space (the old library's `gone`). The flag is read at the start of every pass. | Matches the common intent. Toggling `isHidden` does not itself trigger layout in UIKit, so call `setNeedsLayout()` afterwards. To hide but *keep* the space, use `alpha = 0` instead. |
| **Right-to-left** | Direction follows `effectiveUserInterfaceLayoutDirection` of the container, so `leading` / `trailing` insets and `Row` order flip automatically. | Insets are logical only (`leading` / `trailing`); there is no physical `left` / `right`. Use `.custom` if you really need one. |
| **Pixel alignment** | Taffy's own integer rounding is **off**. Frames are snapped to the screen's `scale` by the framework (0.5pt steps on 2x, 0.333pt on 3x). | Taffy rounds to whole points, which makes 2x/3x screens blurry or gappy. Snapping happens once on the final result, so accumulated rounding error does not leak into siblings. |
| **Safe area** | **Not** applied by default. Opt in on the top-level container: `FlexView(insets: .safeArea) { … }` or `.layoutMargins`. | Most containers are nested and must not add the inset twice. |

### Other decisions

| Topic | Decision | Alternative not taken, and why |
|---|---|---|
| Engine | `ZDTaffy` (Taffy) | Yoga has no Grid/Block; abstracting over both engines would limit the API to their intersection. |
| Platforms | UIKit only for v1. The core has no UIKit dependency so AppKit / SwiftUI `Layout` adapters can be added later. | Doing all three first would triple the surface before the core is proven. |
| View ownership | You own your views; the DSL describes arrangement. Children are reconciled coarsely (added / removed / reordered by identity), no deep diffing. | A React-style element tree with diffing is a large project and detaches the framework from existing UIKit code. |
| Threading | Everything on the main actor, solved synchronously. The solver itself is a pure function with no actor isolation, so a background mode can be added later. | The old library's background mode needed a pre-measure side table; UIKit text measurement is mostly main-thread only, so the win is small and the complexity large. |
| Scrolling | `FlexScrollView(axis: .vertical)` lays content out with an unbounded main axis and keeps `contentSize` in sync. | Keeping `contentSize` correct by hand is the easiest thing to get wrong. |
| Cells | Rely on UIKit self-sizing. `FlexContentConfiguration { … }` (a `UIContentConfiguration`) lets table / collection cells use the DSL directly. | A template-cell height helper is obsolete once self-sizing and `UIContentConfiguration` exist. |
| Old API | No compatibility layer with ZDFlexLayoutKit. | Carrying the old API would constrain the new design. Behaviours (virtual containers, auto-refresh, cell sizing) are kept as concepts only. |
| Objective-C | Not supported. | Result builders and generics have no ObjC equivalent. |

### Debugging and tests

- `flexView.debugDescription` prints the node tree with frames. A debug overlay that outlines every node is available in `DEBUG` builds only.
- `ZDLayoutCore` is tested with `swift test` on macOS; the UIKit layer is tested with `xcodebuild test` on the iOS Simulator. CI runs them as two jobs.

## License

MIT. Taffy is MIT licensed; BoltFFI is MIT licensed.
