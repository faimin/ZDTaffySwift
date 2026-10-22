# ZDTaffy

[English](README.md) · [中文](README.zh-CN.md)

Swift bindings for [Taffy](https://github.com/DioxusLabs/taffy) (CSS Block, Flexbox and Grid layout in Rust) on Apple platforms, generated with [BoltFFI](https://github.com/boltffi/boltffi).

- Taffy `0.15.0`, BoltFFI `0.31.1`
- iOS 15+, macOS 13+ (device and simulator slices, `arm64` and `x86_64`)
- Complete `Style`: Block, Flexbox and Grid properties (`calc()` is not exposed)
- Leaf measurement via a `Measure` protocol, a closure, or an `async` closure

## Installation

Add the package and pick the products you need (`ZDTaffy` is the bare Taffy binding; the others are layout frameworks built on it):

```swift
.package(url: "https://github.com/faimin/ZDTaffySwift", from: "0.1.0")
```

| Product | For |
|---|---|
| `ZDTaffy` | Taffy itself (`TaffyTree`, `Style`) |
| `ZDLayoutCore` | The platform-agnostic layout model and solver |
| `ZDLayout` | UIKit |
| `ZDLayoutSwiftUI` | SwiftUI (`Layout`) |
| `ZDLayoutAppKit` | AppKit |

A tagged release downloads a prebuilt XCFramework (about 36 MB zipped; linking dead-strips what you do not use). Building from `main` needs Rust: see below.

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

### Releasing

`main` points its binary target at the locally built `Artifacts/ZDTaffy.xcframework`. A release builds the framework, zips it and checksums it, then creates a commit that differs from `main` only in the binary target (now the URL of the zip attached to the GitHub release), tags that commit, and publishes the release. The release commit is never merged into `main`.

```bash
scripts/release.sh 0.2.0              # dry run: build, zip, checksum, write build/release/Package.swift
scripts/release.sh 0.2.0 --publish    # tag, push the tag and create the GitHub release (needs a clean tree and gh)
```

The same thing runs from the *Release* workflow in the Actions tab.

## ZDLayout

`ZDLayout` is a declarative layout framework for UIKit built on top of `ZDTaffy`. This section records the agreed design and the trade-offs behind it.

**Status:** implemented and tested. `ZDLayoutCore` runs on macOS (`swift test`); `ZDLayout` (`FlexView`, `FlexScrollView`, `UIView` leaves, `FlexContentConfiguration`) is tested on the iOS Simulator, including self-sizing collection view cells. `ZDLayoutSwiftUI` and `ZDLayoutAppKit` are tested on macOS. (The debug overlay exists in `DEBUG` builds.)

### Goals

- Describe layout and view hierarchy in one place — no manual `addSubview` / `addChildren` / `markDirty`.
- Strongly typed values instead of `YGValue`.
- Participate in UIKit's own layout cycle (`layoutSubviews`, Auto Layout, self-sizing cells) instead of running beside it.
- Flexbox, Block **and CSS Grid**, powered by Taffy.

### Modules

| Target | Depends on | Contents |
|---|---|---|
| `ZDLayoutCore` | `ZDTaffy` | Platform-agnostic: node tree, `Style` builders, solver, measure protocol, guides. No UIKit, so `swift test` on macOS covers it. |
| `ZDLayout` | `ZDLayoutCore`, UIKit | `FlexView`, `FlexScrollView`, `FlexGuide`, DSL, `UIView` adapters, `FlexContentConfiguration`. |
| `ZDLayoutSwiftUI` | `ZDLayoutCore`, SwiftUI | `FlexLayout` / `FlexStack` (a SwiftUI `Layout`), `.flexItem`, `.gridItem`. |
| `ZDLayoutAppKit` | `ZDLayoutCore`, AppKit | `FlexView` and `NSView` adapters for macOS. |

Requirements: Swift 6 language mode, iOS 15+. Everything UIKit-facing is `@MainActor`.

### Usage sketch

```swift
import ZDLayout

final class ProfileHeader: FlexView {
    let avatar = UIImageView()
    let name = UILabel()
    let badge = BadgeView()

    // Re-evaluated on every layout pass, so it can read your state directly.
    // Swift does not carry a result builder over to an override: repeat `@LayoutBuilder`.
    @LayoutBuilder override func body() -> [LayoutNode] {
        Row(gap: 12, alignItems: .center) {
            avatar.size(40)
            Column(gap: 4) {
                name.shrink(1)
                Row {
                    Spacer()
                    badge
                }
            }
            .grow(1)
            .shrink(1)
        }
        .padding(16)
    }
}

// Or, without subclassing:
let header = FlexView(insets: .layoutMargins) {
    Row(gap: 8) { icon.size(24); title.grow(1).shrink(1) }
}
```

- **Containers**: `Row`, `Column`, `Flex(direction:wrap:)`, `Grid`, plus `Spacer`. There is no `ZStack`; make a child overlap with `.absolute(inset:)`.
- **Leaves**: any `UIView` you own can be placed in the builder directly, or let the host create the view for you with `Label`, `Image`, `Box` or `Managed` (see below).
- **Modifiers** (`.width`, `.height`, `.size`, `.grow`, `.shrink`, `.basis`, `.margin`, `.padding`, `.absolute(inset:)`, `.gridColumn(_:span:)`, `.hidden()`, `.styled { }`, …) all edit one value type, `Style`, which mirrors `ZDTaffy.Style`. `.styled { $0.… }` edits the full `LayoutStyle`, and `.custom { $0.… }` reaches the underlying `ZDTaffy.Style`, so nothing Taffy can do is out of reach.
- **Values**: numbers are points (`.width(100)`); a `CGFloat` variable works too (`.height(1 / scale)`); percentages are `.percent(50)` or `50.percent`. There is deliberately no `50%` operator. Public API uses `CGFloat`; the conversion to Taffy's `Float` is internal.

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
- Within a pass the engine asks each leaf about a handful of different sizes (about seven: how big with no limit, how small, how tall at this width, …), almost never the same one twice, since it caches a node's results itself. So there is nothing to gain from memoising inside a `LeafMeasure`.
- `Measure` must be a pure function of the view's current state and the constraint.

### Trade-off: UIKit environment semantics are automatic

| Concern | Behaviour | Why / what to know |
|---|---|---|
| **Hidden views** | A view with `isHidden == true` is treated as `display: none` and takes no space (the old library's `gone`). The flag is read at the start of every pass. | Matches the common intent. Toggling `isHidden` does not itself trigger layout in UIKit, so call `setNeedsLayout()` afterwards. To hide but *keep* the space, use `alpha = 0` instead. |
| **Right-to-left** | The nearest view that forces a `semanticContentAttribute` (the container or an ancestor) decides, otherwise the system direction, so `leading` / `trailing` insets and `Row` order flip automatically. | Insets are logical only (`leading` / `trailing`); there is no physical `left` / `right`. Use `.custom` if you really need one. |
| **Pixel alignment** | Taffy's own integer rounding is **off**. Frames are snapped to the screen's `scale` by the framework (0.5pt steps on 2x, 0.333pt on 3x). Boxes snap both edges, so neighbours stay flush; views with measured content snap their origin and round their size **up**. | Taffy rounds to whole points, which makes 2x/3x screens blurry or gappy. Snapping happens once on the final result, so rounding error does not accumulate. Rounding content up matters: a label snapped a third of a point narrower than its text truncates (`128` became `1…` in the demo). |
| **Safe area** | **Not** applied by default. Opt in on the top-level container: `FlexView(insets: .safeArea) { … }` or `.layoutMargins`. | Most containers are nested and must not add the inset twice. A `FlexScrollView` already makes room for the safe area through `contentInsetAdjustmentBehavior`, so it ignores the safe area in `.layoutMargins` (otherwise the content starts a whole navigation bar too low). |

### Trade-off: items do not shrink by default

CSS gives every flex item `flex-shrink: 1`. ZDLayout defaults to `0`, like Yoga (the old library) and SwiftUI:

| | Behaviour | Cost |
|---|---|---|
| **Chosen: `shrink` = 0** | A view you gave `size(40)` stays 40 wide. Content taller than its container overflows instead of being squashed. | A label that must wrap or truncate next to other views needs an explicit `.shrink(1)`. |
| CSS default: `shrink` = 1 | Items give up space when the container is too small. | Every fixed-size icon needs `.shrink(0)`, and a column inside a short container squashes its rows (this broke self-sizing cells during development: the content was compressed to the cell's estimated height). |

Rule of thumb: put `.shrink(1)` on the text that should wrap or truncate, and on the containers that hold it.

### SwiftUI

`ZDLayoutSwiftUI` gives SwiftUI the same engine through its `Layout` protocol (iOS 16 / macOS 13+):

```swift
import ZDLayoutSwiftUI

FlexStack(.row, gap: 12, alignItems: .center) {
    Circle().frame(width: 40, height: 40)
    Text("A title that wraps when it has to").flexItem(grow: 1, shrink: 1)
    Text("12m").foregroundStyle(.secondary)
}

FlexStack(columns: [.fr(1), .fr(1), .fr(2)], gap: 8) {          // CSS Grid
    ForEach(items) { ItemView($0) }
    Banner().gridItem(column: .line(1, span: 3))
}
```

- `.flexItem(grow:shrink:basis:alignSelf:margin:)` or `.flexItem { $0.… }` (an `ItemStyle`) sets a child's properties; `.gridItem(column:row:)` places it in a grid.
- Children are measured with `subview.sizeThatFits(_:)`: the smallest size is proposed as `0` and the ideal size as `nil`, which is how SwiftUI spells them.
- A SwiftUI container decides its own size. Like an `HStack` holding a `Spacer`, a `FlexStack` with a `grow` child (or `fr` tracks) takes all it is offered along that axis; otherwise it is as large as its content.
- **Right-to-left is mirrored by SwiftUI itself** for any custom `Layout`, so `FlexLayout` always solves left to right. (The UIKit and AppKit containers, in contrast, solve in the real direction because nobody mirrors them.) Use `leading` / `trailing` edges and they flip as expected.
- Shrink defaults to `0` here too, so give wrapping text `shrink: 1`.

### AppKit

`ZDLayoutAppKit` is a leaner port of the UIKit layer to `NSView`: `FlexView` (flipped, so the origin is the top-left), any `NSView` as a leaf, `Label` / `Image` / `Box` / `Managed`, hidden views, right-to-left from `userInterfaceLayoutDirection`, backing-scale pixel alignment, and `FlexInsets.safeArea`. Text fields are measured through their cell at the offered width, with the same smallest-width rule as `UILabel`.

It has no `FlexScrollView`, `FlexGuide`, asynchronous layout or cell configuration. Put a `FlexView` in an `NSScrollView` as its document view to scroll, and call `needsLayout = true` after changing state.

### Asynchronous layout

`layoutSubviews` cannot wait, so it only measures synchronously. When a leaf's size genuinely needs `await` (a background text engine, an image whose size is still loading), adopt `AsyncLayoutMeasurable` and call `layoutAsync()`:

```swift
final class RemoteImageView: UIImageView, AsyncLayoutMeasurable {
    func layoutSize(for constraint: MeasureConstraint) async -> CGSize {
        await loader.pixelSize(of: url)          // the main actor is free while this runs
    }
}

await flexView.layoutAsync()                     // FlexScrollView has it too, and updates contentSize
let size = await flexView.sizeThatFitsAsync(CGSize(width: 320, height: .greatestFiniteMagnitude))
```

- The layout algorithm is synchronous, so it is run again until a pass needs no new measurements. A leaf can therefore be asked about sizes that end up unused, and must answer the same question the same way every time (answer from state, not from a counter or a clock). If the answers never settle, solving throws `TaffyError.measureDidNotConverge` and the layout is left as it was.
- Views are only touched on the main actor. `layoutAsync()` and `AsyncLayoutMeasurable.layoutSize(for:)` are main-actor methods that `await`; it is the waiting that does not block.
- A view that adopts the protocol still goes through the ordinary pass in `layoutSubviews`, which uses its `sizeThatFits` / `intrinsicContentSize` as an estimate. Make those return the last known size so the first frame is close.
- In `ZDLayoutCore`, `Leaf(asyncMeasure:)` and `LayoutSolver.solveAsync(…)` do the same without UIKit. A leaf that only has a synchronous `measure` is called on the caller's actor.

This does not move the solver off the main thread: measuring was the expensive part, and UIKit text measurement is mostly main-thread only (see the trade-off above).

### Performance

Every layout pass measures every leaf again (see the trade-off above), so the cost scales with the number of leaves. Measured in a Release build on the iOS Simulator (Apple silicon), a pass over rows of `icon | wrapping label | time label`:

| Rows | Leaves | One layout pass |
|---|---|---|
| 10 | 30 | ≈ 0.7 ms |
| 50 | 150 | ≈ 3.5 ms |
| 100 | 300 | ≈ 6.5 ms |
| 250 | 750 | ≈ 18 ms |

That is about 22 µs per leaf, so a typical screen (tens of leaves) costs a couple of milliseconds, and a cell of ten leaves a fraction of one. A device is slower than the simulator's host; leave headroom. For a very long list use a reusing container (`UICollectionView`, `UITableView`) and `FlexContentConfiguration`, which lays out only visible cells, rather than one `FlexScrollView` with hundreds of rows.

What the measurements found, and what was done about it:

- Asking a `UILabel` for its smallest width meant measuring its longest words with `boundingRect` on every pass: ~70% of the time. The widest word is now remembered by content (text and font): a 250-row pass went from 73 ms to 27 ms. `UILabel.sizeThatFits` itself is cheap (about 0.3 µs per question once UIKit has cached the text layout).
- The engine used to cross the BoltFFI boundary once per node, encoding a whole `Style` each time (`newLeaf` ≈ 3.5 µs, while Taffy's own work is under 1 µs), and once per measure question with typed parameters. The solver now sends the whole tree in one call (distinct styles once, nodes as a flat list of small records) and measure questions as plain numbers. On macOS a node went from about 9 µs to about 2.5 µs (2,500 nodes: 22 ms to 6 ms), and a 250-row UIKit pass from 27 ms to 18 ms.
- What is left is mostly UIKit itself: creating and updating the views a pass describes, and setting frames.

Reproduce: `cd Benchmarks && swift run -c release ZDLayoutBench` (solver only, macOS), and `TEST_RUNNER_ZDLAYOUT_PERF=1 xcodebuild test -scheme ZDTaffy-Package -configuration Release ENABLE_TESTABILITY=YES -only-testing:ZDLayoutTests/PerformanceReport -destination "id=$(scripts/latest-iphone-simulator.sh)" 2>&1 | grep -A8 PERFREPORT` (real UIKit views).

### How UIKit views are measured

A `UIView` placed in the builder is a leaf. Its content size comes from, in order:

1. `LayoutMeasurable.layoutSize(for:)` if the view adopts it (`FlexView` and `FlexScrollView` do).
2. `UILabel`'s minimum width when the engine asks for the smallest possible size: the longest word if it can wrap, nothing if it is a single truncating line. This is what lets a long title shrink next to an icon instead of refusing to.
3. `sizeThatFits(_:)` if the class overrides it. The width is the space offered, or the width the layout already fixed. The **height is never limited**: `UILabel` drops lines that do not fit a finite height, and an offered height is room, not a clip.
4. Otherwise `intrinsicContentSize`. (A plain `UIView` answers `sizeThatFits` with its current size, which would make the layout feed on itself.)

A plain `UIView()` has no size of its own: give it `.size(…)` or a `LayoutMeasurable` conformance.

### Cells and Auto Layout

`FlexView` reports `intrinsicContentSize` (natural width, and the height for its current width) and implements `systemLayoutSizeFitting`, so it works inside Auto Layout and self-sizing cells. `FlexContentConfiguration` uses it:

```swift
cell.contentConfiguration = FlexContentConfiguration(insets: .layoutMargins) {
    Row(gap: 8, alignItems: .center) { icon.size(24); title.grow(1).shrink(1) }
}
```

Height depends on width, but Auto Layout only asks for an intrinsic size. Like `UILabel`, `FlexView` reports the height for the width it has and, when that width changes, calls `invalidateIntrinsicContentSize()` once from `layoutSubviews`. This is verified on the simulator with both a `UICollectionView` list and a `UITableView` using `automaticDimension`.

### Views the framework creates

Besides your own `UIView`s, a few thin wrappers describe views that the host creates, caches and updates for you: `Label("text", font:color:lines:)`, `Image(image, tint:)`, `Box(color:cornerRadius:)`, and `Managed<V>(make:update:)` for any other type.

```swift
Managed<UISwitch>(id: "notifications", make: { UISwitch() }) { $0.isOn = isOn }
```

`body()` runs on every layout pass, so these are descriptions, not views: the view behind one is cached and reused, and `update` is applied to it each pass. A view's identity is its `id`, or else its position among the un-named descriptions of the same type. Giving views that carry state (animations, text fields) an `id` keeps them stable when an `if` adds or removes an earlier sibling. Cached views the description stops mentioning are removed. Use `Managed<UISwitch>(…)` explicitly when `make` is a multi-statement closure, because Swift cannot infer the type from it.

`Label` wraps by default; give it `.shrink(1)` to make it wrap or truncate beside other views.

### Virtual containers

`Row`, `Column`, `Flex`, `Grid` and `Spacer` are layout nodes only: they never create a `UIView`, so the view hierarchy contains just the leaves, however deeply the description nests. This is what `UILayoutGuide` / ZDFlexLayoutKit's `ZDFlexLayoutDiv` are used for elsewhere.

To get at a virtual container (to read its frame, or pin an ordinary view to it with Auto Layout), attach a guide with `.guide(_:)`:

```swift
let stats = FlexGuide()

Row(gap: 12) { stat("128", "Posts"); stat("4.2K", "Followers") }.guide(stats)

stats.whenInstalled { guide in                       // a real UILayoutGuide
    NSLayoutConstraint.activate([
        background.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: -8),
        background.topAnchor.constraint(equalTo: guide.topAnchor, constant: -8),
        background.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: 16),
        background.heightAnchor.constraint(equalTo: guide.heightAnchor, constant: 16),
    ])
}
stats.frame                                          // or just read it after layout
```

- `LayoutGuide` (in `ZDLayoutCore`) only records the frame. `FlexGuide` (in `ZDLayout`) also owns a `UILayoutGuide`: the host installs it during layout and pins it with four constant constraints, which it updates only when the frame changes, so a steady layout costs no extra Auto Layout pass. It is removed when the description stops mentioning the guide.
- Create constraints inside `whenInstalled`. Before the first layout the `UILayoutGuide` has no view to belong to, and activating a constraint that mentions it would throw.
- Frames are physical (`left`/`top`), so use `leftAnchor`, not `leadingAnchor`, to line up with them in right-to-left layouts.
- In a `FlexScrollView` the guide is measured from a hidden zero-size view parked at the content origin. A scroll view's own edges (and its `contentLayoutGuide`) move with `contentOffset` in Auto Layout, which would shift every follower by the current offset.

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

### Demo

`Demo/` is a small app (profile, grid gallery, self-sizing feed, settings form) that exercises the framework on a real screen. Generate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and run it:

```bash
cd Demo && xcodegen generate && open ZDLayoutDemo.xcodeproj
```

Launch arguments `-tab 0…3` and `-rtl YES` pick a screen and right-to-left layout, which is handy for screenshots.

### Debugging and tests

- `flexView.debugDescription` prints the node tree with frames. A debug overlay that outlines every node is available in `DEBUG` builds only.
- `ZDLayoutCore` is tested with `swift test` on macOS; the UIKit layer is tested with `xcodebuild test` on the iOS Simulator. CI runs them as two jobs.

## License

MIT. Taffy is MIT licensed; BoltFFI is MIT licensed.
