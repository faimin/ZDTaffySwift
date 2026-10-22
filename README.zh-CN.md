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

## ZDLayout

`ZDLayout` 是在 `ZDTaffy` 之上构建的 UIKit 声明式布局框架。本节记录已经确认的设计和取舍。

**进度:** 已实现并通过测试。`ZDLayoutCore` 在 macOS 上用 `swift test` 运行;`ZDLayout`(`FlexView`、`FlexScrollView`、`UIView` 叶子、`FlexContentConfiguration`)在 iOS 模拟器上测试,包括 self-sizing 的 collection view cell。尚未完成:AppKit / SwiftUI 适配。(`DEBUG` 构建里有调试叠加层。)

### 目标

- 布局和视图层级在同一处描述,不再需要手动 `addSubview` / `addChildren` / `markDirty`。
- 使用强类型的值,而不是 `YGValue`。
- 参与 UIKit 自己的布局周期(`layoutSubviews`、Auto Layout、self-sizing cell),而不是在旁边另起一套。
- 由 Taffy 驱动,支持 Flexbox、Block 以及 **CSS Grid**。

### 模块

| Target | 依赖 | 内容 |
|---|---|---|
| `ZDLayoutCore` | `ZDTaffy` | 与平台无关:节点树、`Style` 构造、求解器、测量协议。不依赖 UIKit,可在 macOS 上 `swift test`。 |
| `ZDLayout` | `ZDLayoutCore`、UIKit | `FlexView`、`FlexScrollView`、DSL、`UIView` 适配、`FlexContentConfiguration`。 |

要求:Swift 6 语言模式,iOS 15+。所有面向 UIKit 的 API 都是 `@MainActor`。

### 用法草案

```swift
import ZDLayout

final class ProfileHeader: FlexView {
    let avatar = UIImageView()
    let name = UILabel()
    let badge = BadgeView()

    // 每次布局都会重新求值,所以可以直接读取你的状态。
    // Swift 不会把 result builder 带到重写的方法上:要重复写 `@LayoutBuilder`。
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

// 或者不用子类:
let header = FlexView(insets: .layoutMargins) {
    Row(gap: 8) { icon.size(24); title.grow(1).shrink(1) }
}
```

- **容器**:`Row`、`Column`、`Flex(direction:wrap:)`、`Grid`,以及 `Spacer`。没有 `ZStack`;需要重叠时给子项加 `.absolute(inset:)`。
- **叶子**:任何你自己持有的 `UIView` 都可以直接放进 builder;也可以用 `Label`、`Image`、`Box`、`Managed` 让宿主替你创建视图(见下文)。
- **修饰符**(`.width`、`.height`、`.size`、`.grow`、`.shrink`、`.basis`、`.margin`、`.padding`、`.absolute(inset:)`、`.gridColumn(_:span:)`、`.hidden()`、`.styled { }` 等)修改的都是同一个值类型 `Style`,它对应 `ZDTaffy.Style`。`.styled { $0.… }` 修改完整的 `LayoutStyle`,`.custom { $0.… }` 则直接访问底层的 `ZDTaffy.Style`,所以 Taffy 能做的事都能做到。
- **值**:数字就是 point(`.width(100)`);`CGFloat` 变量也可以(`.height(1 / scale)`);百分比写 `.percent(50)` 或 `50.percent`,有意不提供 `50%` 运算符。公开 API 统一用 `CGFloat`,转成 Taffy 的 `Float` 在内部完成。

```swift
Grid(columns: [.fixed(80), .fr(1), .fr(2)], rows: [.auto], gap: 8) {
    icon
    title.gridColumn(2, span: 2)
}
```

Grid 暴露轨道(`.fixed`、`.fr`、`.auto`、`.minmax`、`.repeat`)、`gap`、`autoFlow`,以及按线 / 跨度放置子项。命名区域和命名线不在 DSL 里,用 `.custom { $0.gridTemplateAreas = … }` 设置。

### 布局如何触发(你需要做什么)

`FlexView` 是一个 `UIView`,在 `layoutSubviews` 里求解,并实现 `sizeThatFits(_:)` / `intrinsicContentSize`。因此它能用在 Auto Layout、`UIStackView`、self-sizing cell 里,也能配合 `UIView.animate { view.layoutIfNeeded() }` 做动画。

**触发布局的方式和 UIKit 一致:调用 `setNeedsLayout()`**(视图报告的尺寸变化时调用 `invalidateIntrinsicContentSize()`)。没有 `markDirty`,也没有私有的 RunLoop 观察者,请求的合并交给 UIKit。

### 取舍:叶子视图的测量结果不跨布局缓存

`UILabel` 的文本变化时,UIKit 不会通知父级。有两种设计:

| | 行为 | 代价 |
|---|---|---|
| **采用:每次布局都重新测量** | 每次布局都对所有叶子调用 `sizeThatFits`,布局的是"当下"的真实状态。 | 每次布局几十次 `sizeThatFits` 调用。 |
| 显式失效(ZDFlexLayoutKit 的做法) | 叶子尺寸会一直缓存,直到你调用 `markDirty`。 | 忘记 `markDirty` 就悄悄显示旧布局,这是旧库最常见的 bug。 |

由此带来的结果:

- 修改 label 的文字、字体或图片后,调用 `flexView.setNeedsLayout()`(基于 frame 的 UIKit 布局本来就要这样做)。你不需要知道是哪个节点变了。
- 如果一个页面有几百个叶子,每次布局就要测量几百次。若性能分析显示这是瓶颈,可以加一个按 `(视图, 尺寸约束)` 为键的可选缓存;它不是默认行为,因为"可能过期的缓存"比"慢一点"更糟。
- 单次布局内部的测量是有记忆的,求解器对同一个叶子问两次同样的问题,只会测量一次。
- 测量必须是视图当前状态和约束的纯函数。

### 取舍:UIKit 环境语义自动处理

| 方面 | 行为 | 原因 / 需要知道的 |
|---|---|---|
| **隐藏视图** | `isHidden == true` 的视图被当作 `display: none`,不占空间(相当于旧库的 `gone`)。每次布局开始时读取。 | 符合最常见的意图。UIKit 里切换 `isHidden` 本身不会触发布局,切换后要调用 `setNeedsLayout()`。想隐藏但保留占位,用 `alpha = 0`。 |
| **从右到左** | 由最近一个强制了 `semanticContentAttribute` 的视图(容器自己或祖先)决定,否则取系统方向,`leading` / `trailing` 内边距和 `Row` 的顺序自动翻转。 | 边距只有逻辑方向(`leading` / `trailing`),没有物理的 `left` / `right`;确实需要时用 `.custom`。 |
| **像素对齐** | 关闭 Taffy 自带的整数取整,由框架按屏幕 `scale` 对齐(2x 屏 0.5pt 步长,3x 屏 0.333pt)。盒子左右边缘各自对齐,相邻节点保持贴合;有内容测量的视图,位置取整、尺寸**向上**取整。 | Taffy 取整到整数 point,在 2x / 3x 屏上会模糊或出现缝隙。对齐只在最终结果上做一次,舍入误差不会累积。内容向上取整很关键:标签被对齐得比文字窄 1/3pt 就会截断(Demo 里 `128` 曾变成 `1…`)。 |
| **安全区** | 默认**不**考虑。在顶层容器上显式开启:`FlexView(insets: .safeArea) { … }` 或 `.layoutMargins`。 | 大多数容器是嵌套的,不能重复加内边距。`FlexScrollView` 已经通过 `contentInsetAdjustmentBehavior` 给安全区留了位置,所以它在 `.layoutMargins` 里忽略安全区(否则内容会整整低一个导航栏的高度)。 |

### 取舍:子项默认不收缩

CSS 给每个 flex 子项默认 `flex-shrink: 1`。ZDLayout 默认是 `0`,与 Yoga(旧库)和 SwiftUI 一致:

| | 行为 | 代价 |
|---|---|---|
| **采用:`shrink` = 0** | 你设了 `size(40)` 的视图就是 40 宽。内容比容器高时溢出,而不是被压扁。 | 需要在其他视图旁边换行或截断的 label,要显式写 `.shrink(1)`。 |
| CSS 默认:`shrink` = 1 | 容器不够大时子项让出空间。 | 每个固定尺寸的图标都要写 `.shrink(0)`;矮容器里的 column 会压扁它的行(开发过程中 self-sizing cell 就因此被压成了预估高度)。 |

经验法则:在需要换行或截断的文本上写 `.shrink(1)`,同时在包着它的容器上也写。

### UIKit 视图如何测量

放进 builder 的 `UIView` 是叶子,内容尺寸依次来自:

1. 如果视图遵循 `LayoutMeasurable`,用它的 `layoutSize(for:)`(`FlexView` 和 `FlexScrollView` 已遵循)。
2. 引擎询问"最小可能尺寸"时,`UILabel` 的最小宽度:能换行就是最长单词的宽度,单行截断就是 0。这样长标题才会在图标旁边收缩,而不是死活不让。
3. 类覆写了 `sizeThatFits(_:)` 时用它。宽度是提供的空间或布局已经确定的宽度;**高度永远不设限**:`UILabel` 会丢掉放不进有限高度的行,而"提供的高度"只是空间,不是裁剪。
4. 否则用 `intrinsicContentSize`。(普通 `UIView` 的 `sizeThatFits` 返回自己当前的尺寸,会让布局结果反过来喂给自己。)

直接 `UIView()` 没有自己的尺寸:要给它 `.size(…)`,或者让它遵循 `LayoutMeasurable`。

### Cell 与 Auto Layout

`FlexView` 报告 `intrinsicContentSize`(自然宽度,以及当前宽度下的高度)并实现 `systemLayoutSizeFitting`,所以能用在 Auto Layout 和 self-sizing cell 里。`FlexContentConfiguration` 就是基于它:

```swift
cell.contentConfiguration = FlexContentConfiguration(insets: .layoutMargins) {
    Row(gap: 8, alignItems: .center) { icon.size(24); title.grow(1).shrink(1) }
}
```

高度取决于宽度,但 Auto Layout 只会询问固有尺寸。和 `UILabel` 一样,`FlexView` 报告的是当前宽度下的高度,宽度变化时在 `layoutSubviews` 里调用一次 `invalidateIntrinsicContentSize()`。这一点已在模拟器上用 `UICollectionView` 列表和使用 `automaticDimension` 的 `UITableView` 验证。

### 由框架创建的视图

除了你自己的 `UIView`,还有几个薄封装用来描述由宿主创建、缓存和更新的视图:`Label("text", font:color:lines:)`、`Image(image, tint:)`、`Box(color:cornerRadius:)`,以及用于其他类型的 `Managed<V>(make:update:)`。

```swift
Managed<UISwitch>(id: "notifications", make: { UISwitch() }) { $0.isOn = isOn }
```

`body()` 每次布局都会执行,所以它们是"描述"而不是视图:背后的视图被缓存并复用,每次布局都会对它调用 `update`。视图的身份是它的 `id`,没有 `id` 时是它在同类型、无名描述中的位置。带状态的视图(动画、输入框)应该给 `id`,这样前面的兄弟因 `if` 增减时它不会换成另一个对象。描述不再提到的缓存视图会被移除。`make` 是多语句闭包时要显式写 `Managed<UISwitch>(…)`,因为 Swift 无法从多语句闭包推断类型。

`Label` 默认会换行;要让它在其他视图旁边换行或截断,加 `.shrink(1)`。

### 虚拟容器

`Row`、`Column`、`Flex`、`Grid`、`Spacer` 只是布局节点,从不创建 `UIView`:无论描述嵌套多深,视图层级里只有叶子。这正是其他框架里 `UILayoutGuide` / ZDFlexLayoutKit 的 `ZDFlexLayoutDiv` 的用途。

### 其他决策

| 主题 | 决定 | 没有采用的方案及原因 |
|---|---|---|
| 引擎 | `ZDTaffy`(Taffy) | Yoga 没有 Grid / Block;同时抽象两个引擎会让 API 退化到两者的交集。 |
| 平台 | 首版只做 UIKit。核心不依赖 UIKit,以后可加 AppKit / SwiftUI `Layout` 适配。 | 一开始就做三套,会在核心验证之前把工作量翻三倍。 |
| 视图所有权 | 视图由你持有,DSL 只描述排布。子项按身份做粗粒度对账(增、删、重排),不做深度 diff。 | React 式的元素树加 diff 是个大工程,还会让框架和已有 UIKit 代码割裂。 |
| 线程 | 全部在主 actor 上同步求解。求解器本身是不带 actor 隔离的纯函数,以后可以加后台模式。 | 旧库的后台模式需要预测量侧表;UIKit 文本测量大多只能在主线程,收益小、复杂度高。 |
| 滚动 | `FlexScrollView(axis: .vertical)` 沿主轴不限制尺寸地布局内容,并保持 `contentSize` 同步。 | 手动维护 `contentSize` 是最容易出错的地方。 |
| Cell | 依赖 UIKit 原生 self-sizing。`FlexContentConfiguration { … }`(一个 `UIContentConfiguration`)让 table / collection 的 cell 直接用 DSL。 | 有了 self-sizing 和 `UIContentConfiguration`,模板 cell 算高度的辅助类已经过时。 |
| 旧 API | 不提供与 ZDFlexLayoutKit 的兼容层。 | 背负旧 API 会限制新设计。虚拟容器、自动刷新、cell 自适应只作为概念保留。 |
| Objective-C | 不支持。 | result builder 和泛型没有 ObjC 对应物。 |

### Demo

`Demo/` 是一个小 App(个人资料、网格相册、自适应高度的信息流、设置表单),用来在真实屏幕上检验框架。用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成工程并运行:

```bash
cd Demo && xcodegen generate && open ZDLayoutDemo.xcodeproj
```

启动参数 `-tab 0…3` 和 `-rtl YES` 可以选择页面和从右到左布局,截图时很方便。

### 调试与测试

- `flexView.debugDescription` 打印带 frame 的节点树。给每个节点画边框的调试叠加层只在 `DEBUG` 构建中可用。
- `ZDLayoutCore` 用 macOS 上的 `swift test` 测试;UIKit 层用 iOS 模拟器上的 `xcodebuild test` 测试。CI 里分成两个 job。

## 许可

MIT。Taffy 与 BoltFFI 同为 MIT 许可。
