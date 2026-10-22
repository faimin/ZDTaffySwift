# ZDTaffy

[English](README.md) · [中文](README.zh-CN.md)

使用 [BoltFFI](https://github.com/boltffi/boltffi) 为 [Taffy](https://github.com/DioxusLabs/taffy)(Rust 实现的 CSS Block / Flexbox / Grid 布局引擎)生成的 Swift 桥接层,面向 Apple 平台。

- Taffy `0.15.0`,BoltFFI `0.31.1`
- iOS 15+、macOS 13+(真机与模拟器切片,`arm64` 与 `x86_64`)
- 完整的 `Style`:Block、Flexbox、Grid 全部属性(不暴露 `calc()`)
- 叶子节点测量:`Measure` 协议、闭包或 `async` 闭包

## 用法

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

## 需要了解的行为

- `TaffyTree` 线程安全(内部加锁串行化)。**不要**在 `Measure` 回调里再访问同一棵树,会死锁。
- 失效或不属于该树的 `NodeId` 会抛出 `TaffyError`,不会崩溃;会造成环的挂接会被拒绝。
- 生成的绑定以 Swift 5 语言模式编译:BoltFFI 把回调表放在全局 `var` 里,Swift 6 严格并发不接受。使用 Swift 6 的 App 不受影响。

## 构建

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

## 许可

MIT。Taffy 与 BoltFFI 同为 MIT 许可。
