# ZDTaffy

[English](#english) · [中文](#中文)

## English

Swift bindings for [Taffy](https://github.com/DioxusLabs/taffy) (CSS Block, Flexbox and Grid layout in Rust) on Apple platforms, generated with [BoltFFI](https://github.com/boltffi/boltffi).

- Taffy `0.15.0`, BoltFFI `0.31.1`
- iOS 15+, macOS 13+ (device and simulator slices, `arm64` and `x86_64`)
- Complete `Style`: Block, Flexbox and Grid properties (`calc()` is not exposed)
- Leaf measurement via a `Measure` protocol, a closure, or an `async` closure

### Usage

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

### Behaviour worth knowing

- `TaffyTree` is thread-safe (calls are serialized by a lock). Do **not** call the same tree from inside a `Measure` callback; it would deadlock.
- Stale or foreign `NodeId`s throw `TaffyError` instead of crashing, and links that would create a cycle are rejected.
- The generated bindings are compiled in Swift 5 language mode: BoltFFI keeps callback tables in global `var`s that Swift 6 strict concurrency rejects. Apps using Swift 6 are unaffected.

### Building

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

### License

MIT. Taffy is MIT licensed; BoltFFI is MIT licensed.

## 中文

使用 [BoltFFI](https://github.com/boltffi/boltffi) 为 [Taffy](https://github.com/DioxusLabs/taffy)(Rust 实现的 CSS Block / Flexbox / Grid 布局引擎)生成的 Swift 桥接层,面向 Apple 平台。

- Taffy `0.15.0`,BoltFFI `0.31.1`
- iOS 15+、macOS 13+(真机与模拟器切片,`arm64` 与 `x86_64`)
- 完整的 `Style`:Block、Flexbox、Grid 全部属性(不暴露 `calc()`)
- 叶子节点测量:`Measure` 协议、闭包或 `async` 闭包

### 用法

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

测量内容(文本、图片):闭包在布局计算期间被同步调用。

```swift
try tree.computeLayout(root: root, available: .definite(width: 320, height: 480)) { node, known, available in
    // 返回叶子节点 `node` 的内容尺寸
    Size(width: 40, height: 12)
}
```

`known` 是父级布局算法已经确定的尺寸(例如被拉伸的交叉轴);节点自身 style 里设置的尺寸会以 `.definite` 出现在 `available` 中。

如果测量需要挂起(例如在主 actor 上测文本),使用异步版本:

```swift
try await tree.computeLayoutAsync(root: root, available: .maxContent) { node, known, available in
    await MainActor.run { measureText(for: node, in: available.width) }
}
```

布局算法本身是同步的,所以会重复计算直到某一轮不再需要新的测量。因此闭包可能被问到最终用不上的尺寸,并且同样的输入必须返回同样的结果;如果结果始终无法稳定,会抛出 `TaffyError.measureDidNotConverge`。

命名说明:为避免与 Foundation、SwiftUI 和标准库冲突,Taffy 的 `Dimension`、`Layout`、`Float` 在 Swift 里叫 `TaffyDimension`、`NodeLayout`、`FloatSide`。Taffy 的泛型类型(`Size<T>`、`Rect<T>` 等)在这里是具体类型,如 `DimensionSize`、`LengthPercentageRect`。

### 需要了解的行为

- `TaffyTree` 线程安全(内部加锁串行化)。**不要**在 `Measure` 回调里再访问同一棵树,会死锁。
- 失效或不属于该树的 `NodeId` 会抛出 `TaffyError`,不会崩溃;会造成环的挂接会被拒绝。
- 生成的绑定以 Swift 5 语言模式编译:BoltFFI 把回调表放在全局 `var` 里,Swift 6 严格并发不接受。使用 Swift 6 的 App 不受影响。

### 构建

需要 Xcode 16+、Rust(stable,含 Apple 目标)和 BoltFFI CLI:

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin
cargo install boltffi_cli --version 0.31.1

./scripts/build-xcframework.sh   # 生成 Artifacts/ZDTaffy.xcframework 并刷新生成的 Swift 代码
swift test
```

`Artifacts/` 不入库;生成的 Swift(`Sources/ZDTaffy/Generated`)和 C 垫片(`Sources/ZDTaffyFFI`)会提交。目录结构:

| 路径 | 内容 |
|---|---|
| `rust/` | 包装 Taffy 的 Rust crate,带 BoltFFI 标注 |
| `Sources/ZDTaffy/` | 手写的 Swift 便利层 + 生成的绑定 |
| `Tests/ZDTaffyTests/` | Swift Testing 测试 |
| `scripts/` | XCFramework 构建脚本 |

### 许可

MIT。Taffy 与 BoltFFI 同为 MIT 许可。
