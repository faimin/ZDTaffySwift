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

## License

MIT. Taffy is MIT licensed; BoltFFI is MIT licensed.
