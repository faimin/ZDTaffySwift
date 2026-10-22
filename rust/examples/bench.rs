// cargo run --release --example bench
use std::time::Instant;
use zd_taffy::*;

fn per_call(label: &str, n: u32, mut f: impl FnMut()) {
    for _ in 0..3 { f(); }
    let start = Instant::now();
    for _ in 0..5 { f(); }
    let micros = start.elapsed().as_secs_f64() * 1e6 / (5.0 * n as f64);
    println!("  {label:<40}{micros:8.3}");
}

fn main() {
    let n = 5000;
    let style = Style::default();
    println!("Rust side only (microseconds per call)");
    per_call("Style::default()", n, || { for _ in 0..n { std::hint::black_box(Style::default()); } });
    per_call("Style -> taffy::Style (From)", n, || { for _ in 0..n { std::hint::black_box(taffy::Style::from(style.clone())); } });
    per_call("Style clone", n, || { for _ in 0..n { std::hint::black_box(style.clone()); } });
    let tree = TaffyTree::new();
    per_call("TaffyTree::new_leaf(style)", n, || { for _ in 0..n { std::hint::black_box(tree.new_leaf(style.clone()).unwrap()); } });
    let ids: Vec<NodeId> = (0..n).map(|_| tree.new_leaf(style.clone()).unwrap()).collect();
    per_call("TaffyTree::layout(node)", n, || { for id in &ids { std::hint::black_box(tree.layout(*id).unwrap()); } });
}
