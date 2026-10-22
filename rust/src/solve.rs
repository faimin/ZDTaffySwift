//! Whole-tree solving in one call.
//!
//! Building a tree node by node costs a boundary crossing (and a wire-encoded `Style`) per node, which dominated
//! the engine's time. These functions take the whole tree at once: the distinct styles, plus a flat list of
//! nodes in pre-order, each saying which style it uses and how many children follow it. They return every
//! node's layout in the same order.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use boltffi::*;
use taffy::{compute_leaf_layout, TaffyTree as Inner};

use crate::geometry::{AvailableSize, NodeId, Size};
use crate::style::Style;
use crate::tree::{space_key, AsyncMeasure, MeasureKey, NodeLayout, TaffyError, MAX_ASYNC_PASSES};

/// One node of a flattened tree: which entry of the style table it uses and how many children it has. Nodes are
/// listed in pre-order, so a node's children (and their descendants) follow it directly.
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct NodeSpec {
    pub style: u32,
    pub child_count: u32,
}

/// Measures leaves for [`solve_tree`]. It takes only primitives so that the call needs no encoding on either side of
/// the boundary: it runs thousands of times per layout (about seven questions per leaf), and with typed parameters
/// that was most of the time.
#[export]
pub trait TreeMeasure: Send {
    /// - `node`: the leaf's pre-order index.
    /// - `known_*`: a dimension the parent's algorithm has already fixed; only meaningful if its flag is set.
    /// - `available_*`: the space on offer; a number of points if its kind is definite (0), otherwise ignored.
    /// - `flags`: bit 0 / bit 1 say `known_width` / `known_height` are set; bits 2-3 and 4-5 are the kind of
    ///   `available_width` / `available_height`: 0 definite, 1 min-content, 2 max-content.
    fn measure(
        &self,
        node: u32,
        known_width: f32,
        known_height: f32,
        available_width: f32,
        available_height: f32,
        flags: u32,
    ) -> Size;
}

fn space_kind(space: taffy::AvailableSpace) -> (f32, u32) {
    match space {
        taffy::AvailableSpace::Definite(points) => (points, 0),
        taffy::AvailableSpace::MinContent => (0.0, 1),
        taffy::AvailableSpace::MaxContent => (0.0, 2),
    }
}

/// A tree whose node contexts are pre-order indices, which is how measure callbacks identify nodes.
struct Built {
    tree: Inner<u32>,
    ids: Vec<taffy::NodeId>,
}

/// `Inner` is `!Send` only because `CompactLength` packs its tag and `f32` payload into a `*const ()`, which is only
/// dereferenced for `calc()` values that this crate never constructs. The tree is owned by one call at a time.
struct SendBuilt(Built);
unsafe impl Send for SendBuilt {}

fn build(styles: Vec<Style>, nodes: &[NodeSpec]) -> Result<Built, TaffyError> {
    if nodes.is_empty() {
        return Err(TaffyError::InvalidInputNode);
    }
    let styles: Vec<taffy::Style> = styles.into_iter().map(Into::into).collect();
    let mut tree: Inner<u32> = Inner::new();
    // Pixel snapping is done by the caller, on the final result.
    tree.disable_rounding();

    let mut ids = vec![taffy::NodeId::from(0u64); nodes.len()];
    let mut pending: Vec<taffy::NodeId> = Vec::new();
    // Walking a pre-order list backwards finishes every child before its parent.
    for (index, spec) in nodes.iter().enumerate().rev() {
        let style = styles.get(spec.style as usize).ok_or(TaffyError::InvalidInputNode)?.clone();
        let count = spec.child_count as usize;
        let id = if count == 0 {
            tree.new_leaf_with_context(style, index as u32)?
        } else {
            if pending.len() < count {
                return Err(TaffyError::InvalidChildNode);
            }
            let children: Vec<taffy::NodeId> = (0..count).map(|_| pending.pop().expect("length checked")).collect();
            tree.new_with_children(style, &children)?
        };
        ids[index] = id;
        pending.push(id);
    }
    if pending.len() != 1 {
        return Err(TaffyError::InvalidInputNode);
    }
    Ok(Built { tree, ids })
}

fn layouts(built: &Built) -> Vec<NodeLayout> {
    built.ids.iter().map(|id| NodeLayout::from(built.tree.unrounded_layout(*id))).collect()
}

/// Solves a flattened tree. `measure` is asked about leaves, identified by their pre-order index. Returns one
/// layout per node, in pre-order.
#[export]
pub fn solve_tree(
    styles: Vec<Style>,
    nodes: Vec<NodeSpec>,
    available: AvailableSize,
    measure: Box<dyn TreeMeasure>,
) -> Result<Vec<NodeLayout>, TaffyError> {
    let mut built = build(styles, &nodes)?;
    let root = built.ids[0];
    built.tree.compute_layout_with_measure(root, available.into(), |inputs, _node, context, style| {
        let index = context.map_or(0, |c| *c);
        compute_leaf_layout(
            inputs,
            style,
            |_, _| 0.0,
            |known, space| {
                let (available_width, width_kind) = space_kind(space.width);
                let (available_height, height_kind) = space_kind(space.height);
                let flags = known.width.is_some() as u32
                    | (known.height.is_some() as u32) << 1
                    | width_kind << 2
                    | height_kind << 4;
                measure
                    .measure(
                        index,
                        known.width.unwrap_or(0.0),
                        known.height.unwrap_or(0.0),
                        available_width,
                        available_height,
                        flags,
                    )
                    .into()
            },
        )
    })?;
    Ok(layouts(&built))
}

/// Like [`solve_tree`], but `measure` may suspend. The layout is recomputed until a pass asks nothing new, so the
/// same question must always get the same answer.
#[export]
pub async fn solve_tree_async(
    styles: Vec<Style>,
    nodes: Vec<NodeSpec>,
    available: AvailableSize,
    measure: Arc<dyn AsyncMeasure>,
) -> Result<Vec<NodeLayout>, TaffyError> {
    let mut built = SendBuilt(build(styles, &nodes)?);
    let root = built.0.ids[0];
    let mut answers: HashMap<MeasureKey, taffy::geometry::Size<f32>> = HashMap::new();

    for _ in 0..MAX_ASYNC_PASSES {
        let mut asked: HashSet<MeasureKey> = HashSet::new();
        let mut questions: Vec<(MeasureKey, u32, crate::geometry::OptionalSize, AvailableSize)> = Vec::new();

        built.0.tree.compute_layout_with_measure(root, available.into(), |inputs, _node, context, style| {
            let index = context.map_or(0, |c| *c);
            compute_leaf_layout(inputs, style, |_, _| 0.0, |known, space| {
                let key: MeasureKey = (
                    index as u64,
                    [known.width.map(f32::to_bits), known.height.map(f32::to_bits)],
                    [space_key(space.width), space_key(space.height)],
                );
                if let Some(size) = answers.get(&key) {
                    return *size;
                }
                if asked.insert(key) {
                    questions.push((key, index, known.into(), space.into()));
                }
                // Placeholder; the layout is redone once the real answer is known.
                taffy::geometry::Size::ZERO
            })
        })?;

        if questions.is_empty() {
            return Ok(layouts(&built.0));
        }
        // Layouts computed from placeholders must not be served from Taffy's cache next pass.
        for (_, index, _, _) in &questions {
            built.0.tree.mark_dirty(built.0.ids[*index as usize])?;
        }
        for (key, index, known, space) in questions {
            let size: Size = measure.measure(NodeId { raw: index as u64 }, known, space).await;
            answers.insert(key, size.into());
        }
    }
    Err(TaffyError::MeasureDidNotConverge)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::AvailableSpace;
    use crate::style::{Display, TaffyDimension};
    use std::sync::Mutex;

    struct Fixed(Mutex<Vec<u32>>);

    impl TreeMeasure for Fixed {
        fn measure(&self, node: u32, _: f32, _: f32, _: f32, _: f32, _: u32) -> Size {
            self.0.lock().unwrap().push(node);
            Size { width: 30.0, height: 10.0 }
        }
    }

    fn available() -> AvailableSize {
        AvailableSize { width: AvailableSpace::Definite(100.0), height: AvailableSpace::MaxContent }
    }

    fn row() -> Style {
        let mut style = Style::default();
        style.display = Display::Flex;
        style.size.width = TaffyDimension::Length(100.0);
        style
    }

    #[test]
    fn solves_a_flattened_tree_in_pre_order() {
        let measure = Box::new(Fixed(Mutex::new(Vec::new())));
        // root -> [leaf, leaf]
        let nodes = vec![
            NodeSpec { style: 0, child_count: 2 },
            NodeSpec { style: 1, child_count: 0 },
            NodeSpec { style: 1, child_count: 0 },
        ];

        let layouts = solve_tree(vec![row(), Style::default()], nodes, available(), measure).unwrap();

        assert_eq!(layouts.len(), 3);
        assert_eq!(layouts[0].size.width, 100.0);
        assert_eq!((layouts[1].location.x, layouts[1].size.width), (0.0, 30.0));
        assert_eq!((layouts[2].location.x, layouts[2].size.width), (30.0, 30.0));
    }

    #[test]
    fn measure_identifies_leaves_by_pre_order_index() {
        let seen = Arc::new(Mutex::new(Vec::new()));
        struct Recorder(Arc<Mutex<Vec<u32>>>);
        impl TreeMeasure for Recorder {
            fn measure(&self, node: u32, _: f32, _: f32, _: f32, _: f32, _: u32) -> Size {
                self.0.lock().unwrap().push(node);
                Size { width: 1.0, height: 1.0 }
            }
        }
        // root -> [a -> [x, y], z]: leaves are 2, 3 and 4 in pre-order.
        let nodes = vec![
            NodeSpec { style: 0, child_count: 2 },
            NodeSpec { style: 0, child_count: 2 },
            NodeSpec { style: 1, child_count: 0 },
            NodeSpec { style: 1, child_count: 0 },
            NodeSpec { style: 1, child_count: 0 },
        ];

        solve_tree(vec![row(), Style::default()], nodes, available(), Box::new(Recorder(seen.clone()))).unwrap();

        let mut asked = seen.lock().unwrap().clone();
        asked.sort();
        asked.dedup();
        assert_eq!(asked, vec![2, 3, 4]);
    }

    #[test]
    fn measure_receives_the_kind_and_value_of_the_available_space() {
        struct Capture(Arc<Mutex<Vec<(f32, f32, u32)>>>);
        impl TreeMeasure for Capture {
            fn measure(&self, _: u32, _: f32, _: f32, width: f32, height: f32, flags: u32) -> Size {
                self.0.lock().unwrap().push((width, height, flags));
                Size { width: 1.0, height: 1.0 }
            }
        }
        let seen = Arc::new(Mutex::new(Vec::new()));
        let leaf = NodeSpec { style: 0, child_count: 0 };

        solve_tree(vec![Style::default()], vec![leaf], available(), Box::new(Capture(seen.clone()))).unwrap();

        // A lone leaf is offered 100pt of width (definite) and an open height (max-content).
        let (width, _, flags) = seen.lock().unwrap()[0];
        assert_eq!(width, 100.0);
        assert_eq!((flags >> 2) & 0b11, 0, "width kind is definite");
        assert_eq!((flags >> 4) & 0b11, 2, "height kind is max-content");
    }

    #[test]
    fn rejects_malformed_trees() {
        let measure = || Box::new(Fixed(Mutex::new(Vec::new())));
        // No nodes.
        assert!(solve_tree(vec![row()], vec![], available(), measure()).is_err());
        // Style index out of range.
        assert!(solve_tree(vec![row()], vec![NodeSpec { style: 3, child_count: 0 }], available(), measure()).is_err());
        // A node claims more children than follow it.
        assert!(solve_tree(vec![row()], vec![NodeSpec { style: 0, child_count: 2 }], available(), measure()).is_err());
        // Two roots.
        let two_roots = vec![NodeSpec { style: 0, child_count: 0 }, NodeSpec { style: 0, child_count: 0 }];
        assert!(solve_tree(vec![row()], two_roots, available(), measure()).is_err());
    }
}
