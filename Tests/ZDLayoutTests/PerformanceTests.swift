#if canImport(UIKit)
import Foundation
import Testing
import UIKit
import ZDLayoutCore
@testable import ZDLayout

/// Timing report for real UIKit views. It is skipped unless `ZDLAYOUT_PERF` is set, never fails, and only means
/// something in Release:
///
///     TEST_RUNNER_ZDLAYOUT_PERF=1 xcodebuild test -scheme ZDTaffy-Package -configuration Release ENABLE_TESTABILITY=YES \
///       -only-testing:ZDLayoutTests/PerformanceReport -destination 'platform=iOS Simulator,name=iPhone 17' \
///       2>&1 | grep -A8 PERFREPORT
@MainActor
@Suite("Performance report", .serialized, .enabled(if: ProcessInfo.processInfo.environment["ZDLAYOUT_PERF"] != nil))
struct PerformanceReport {
    private func ms(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    private func median(_ runs: Int, _ body: () -> Void) -> Double {
        var samples = (0..<runs).map { _ in ms(body) }
        samples.sort()
        return samples[samples.count / 2]
    }

    @Test func report() throws {
        var lines = ["rows  leaves  cold(ms)  steady(ms)  fit(ms)  UILabel.sizeThatFits-only(ms)  overhead(ms)"]
        for rows in [10, 50, 100, 250, 500] {
            let body = "Item description that is long enough to wrap onto a second line on a phone."
            let view = FlexView {
                Column(gap: 8) {
                    for index in 0..<rows {
                        Row(gap: 12, alignItems: .center) {
                            Box(color: .systemBlue, cornerRadius: 20, id: "icon\(index)").size(40)
                            Label(body, font: .systemFont(ofSize: 15), lines: 0, id: "t\(index)").grow(1).shrink(1)
                            Label("\(index)m", font: .systemFont(ofSize: 12), lines: 1, id: "m\(index)")
                        }
                        .padding(12)
                    }
                }
            }
            view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

            let cold = ms { view.layoutIfNeeded() }
            let steady = median(15) { view.setNeedsLayout(); view.layoutIfNeeded() }
            let fit = median(5) { _ = view.sizeThatFits(CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude)) }

            // What UIKit itself spends measuring the same labels, once each at the final width.
            let labels = view.subviews.compactMap { $0 as? UILabel }
            let measureOnly = median(5) {
                for label in labels { _ = label.sizeThatFits(CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)) }
            }
            lines.append(String(format: "%4d  %6d  %8.2f  %10.2f  %7.2f  %29.2f  %12.2f",
                                rows, rows * 3, cold, steady, fit, measureOnly, max(steady - measureOnly, 0)))
        }
        let report = lines.joined(separator: "\n") + "\n"
        // stderr reaches the xcodebuild log; grep for "PERFREPORT".
        FileHandle.standardError.write(Data(("PERFREPORT\n" + report).utf8))
        #expect(!lines.isEmpty)
    }
}
#endif

#if canImport(UIKit)
/// Counts and times the measure questions UIKit views are asked.
@MainActor
private final class CountingLabel: UILabel {
    static var calls = 0
    static var nanos: UInt64 = 0
    static func reset() { calls = 0; nanos = 0 }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = super.sizeThatFits(size)
        Self.nanos += DispatchTime.now().uptimeNanoseconds - start
        Self.calls += 1
        return result
    }
}

@MainActor
extension PerformanceReport {
    @Test func breakdown() throws {
        var lines = ["rows  labels  pass(ms)  measure-calls  measure(ms)  per-call(us)  everything-else(ms)"]
        for rows in [10, 50, 100, 250] {
            let body = "Item description that is long enough to wrap onto a second line on a phone."
            let view = FlexView {
                Column(gap: 8) {
                    for index in 0..<rows {
                        Row(gap: 12, alignItems: .center) {
                            Box(color: .systemBlue, cornerRadius: 20, id: "icon\(index)").size(40)
                            Managed<CountingLabel>(id: "t\(index)", make: {
                                let label = CountingLabel()
                                label.numberOfLines = 0
                                label.font = .systemFont(ofSize: 15)
                                return label
                            }) { $0.text = body }
                            .grow(1).shrink(1)
                            Label("\(index)m", font: .systemFont(ofSize: 12), lines: 1, id: "m\(index)")
                        }
                        .padding(12)
                    }
                }
            }
            view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            view.layoutIfNeeded()

            var best = Double.greatestFiniteMagnitude
            var calls = 0
            var measureMs = 0.0
            for _ in 0..<5 {
                CountingLabel.reset()
                let start = DispatchTime.now().uptimeNanoseconds
                view.setNeedsLayout()
                view.layoutIfNeeded()
                let total = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                if total < best { best = total; calls = CountingLabel.calls; measureMs = Double(CountingLabel.nanos) / 1e6 }
            }
            lines.append(String(format: "%4d  %6d  %8.2f  %13d  %11.2f  %12.2f  %19.2f",
                                rows, rows, best, calls, measureMs, calls == 0 ? 0 : measureMs * 1000 / Double(calls), best - measureMs))
        }
        FileHandle.standardError.write(Data(("PERFBREAKDOWN\n" + lines.joined(separator: "\n") + "\n").utf8))
    }
}
#endif
