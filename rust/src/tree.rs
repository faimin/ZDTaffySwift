//! The exported `TaffyTree` handle and the measure callback.

use std::collections::{HashMap, HashSet};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, Mutex};

use boltffi::*;
use taffy::{compute_leaf_layout, TaffyTree as Inner};

use crate::geometry::{AvailableSize, AxisFlags, NodeId, OptionalSize, Point, Rect, Size};
use crate::grid::GridLayoutInfo;
use crate::style::Style;

/// Errors reported by tree operations. Mirrors `taffy::TaffyError`.
#[error]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TaffyError {
    /// A child index was past the end of the parent's child list.
    ChildIndexOutOfBounds,
    /// The parent node does not belong to this tree.
    InvalidParentNode,
    /// The child node does not belong to this tree.
    InvalidChildNode,
    /// The node does not belong to this tree.
    InvalidInputNode,
    /// An async measure kept producing new questions; the layout was abandoned.
    MeasureDidNotConverge,
}

impl From<taffy::TaffyError> for TaffyError {
    fn from(e: taffy::TaffyError) -> Self {
        match e {
            taffy::TaffyError::ChildIndexOutOfBounds { .. } => TaffyError::ChildIndexOutOfBounds,
            taffy::TaffyError::InvalidParentNode(_) => TaffyError::InvalidParentNode,
            taffy::TaffyError::InvalidChildNode(_) => TaffyError::InvalidChildNode,
            taffy::TaffyError::InvalidInputNode(_) => TaffyError::InvalidInputNode,
        }
    }
}

/// The computed layout of a node (`taffy::Layout`).
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NodeLayout {
    /// Paint / hit-test order among siblings.
    pub order: u32,
    /// Position relative to the parent's border box.
    pub location: Point,
    /// Size of the node's border box.
    pub size: Size,
    /// The rectangle containing the node's content and its descendants' overflow, relative to the padding box's
    /// top-left corner. It contains the origin: `left` / `top` are not positive, `right` / `bottom` not negative.
    pub scrollable_overflow_rect: Rect,
    /// Per axis, whether scrolling starts at the far edge (right / bottom). True for reversed flex directions
    /// (`row-reverse`, `column-reverse`, `wrap-reverse`) and, horizontally, for right-to-left containers.
    pub scroll_origin_reversed: AxisFlags,
    /// How far the content can scroll horizontally: the overflow beyond the padding box, `0` if it fits.
    pub scroll_width: f32,
    /// How far the content can scroll vertically: the overflow beyond the padding box, `0` if it fits.
    pub scroll_height: f32,
    pub scrollbar_size: Size,
    pub border: Rect,
    pub padding: Rect,
    pub margin: Rect,
}

impl From<&taffy::Layout> for NodeLayout {
    fn from(l: &taffy::Layout) -> Self {
        NodeLayout {
            order: l.order,
            location: l.location.into(),
            size: l.size.into(),
            scrollable_overflow_rect: l.scrollable_overflow_rect.rect().into(),
            scroll_origin_reversed: l.scrollable_overflow_rect.is_reversed().into(),
            scroll_width: l.scroll_width(),
            scroll_height: l.scroll_height(),
            scrollbar_size: l.scrollbar_size.into(),
            border: l.border.into(),
            padding: l.padding.into(),
            margin: l.margin.into(),
        }
    }
}

/// Supplies the intrinsic size of leaf nodes (text, images, ...) during layout.
///
/// It is called synchronously from inside `compute_layout_with_measure`, possibly several
/// times per node, and must not call back into the same tree.
#[export]
pub trait Measure: Send {
    /// - `known`: dimensions the parent's layout algorithm has already fixed (for example a
    ///   stretched cross axis). A size set in the node's own style is *not* reported here; it
    ///   arrives as a `Definite` value in `available`.
    /// - `available`: the space the node may occupy along each axis.
    ///
    /// Return the node's content size, excluding padding and border.
    fn measure(&self, node: NodeId, known: OptionalSize, available: AvailableSize) -> Size;
}

/// Like [`Measure`], but the answer may be produced asynchronously (for example on a main actor).
///
/// The layout algorithm itself is synchronous, so `compute_layout_with_async_measure` runs it
/// repeatedly: every pass collects the questions it could not answer yet, they are awaited
/// outside of the tree lock, and the layout is recomputed until a pass asks nothing new.
/// The answer for a given `(node, known, available)` must therefore be deterministic.
#[export]
#[async_trait::async_trait]
pub trait AsyncMeasure: Send + Sync {
    /// See [`Measure::measure`] for the meaning of the parameters.
    async fn measure(&self, node: NodeId, known: OptionalSize, available: AvailableSize) -> Size;
}

/// Upper bound on layout passes for one async computation.
pub(crate) const MAX_ASYNC_PASSES: usize = 64;

/// Identifies one measure question; floats are compared bit-for-bit.
pub(crate) type MeasureKey = (u64, [Option<u32>; 2], [(u8, u32); 2]);

pub(crate) fn space_key(space: taffy::AvailableSpace) -> (u8, u32) {
    match space {
        taffy::AvailableSpace::Definite(x) => (0, x.to_bits()),
        taffy::AvailableSpace::MinContent => (1, 0),
        taffy::AvailableSpace::MaxContent => (2, 0),
    }
}

struct MeasureQuestion {
    node: NodeId,
    known: OptionalSize,
    available: AvailableSize,
}

/// Tree state behind the mutex.
///
/// Taffy indexes its slot maps directly, so a stale `NodeId` would panic (and a panic cannot
/// unwind across the FFI boundary). `live` lets every call reject unknown ids up front.
struct Core {
    tree: Inner<()>,
    live: HashSet<u64>,
}

/// `taffy::TaffyTree` is `!Send` only because `CompactLength` packs its tag and `f32` payload
/// into a `*const ()`. That pointer is only dereferenced for `calc()` values, which this
/// crate never constructs, so moving the tree between threads is sound.
unsafe impl Send for Core {}

impl Core {
    fn require(&self, id: NodeId, otherwise: TaffyError) -> Result<(), TaffyError> {
        if self.live.contains(&id.raw) { Ok(()) } else { Err(otherwise) }
    }

    fn require_all(&self, ids: &[NodeId], otherwise: TaffyError) -> Result<(), TaffyError> {
        ids.iter().try_for_each(|id| self.require(*id, otherwise))
    }

    /// Rejects links that would make `child` its own ancestor, which would recurse forever during layout.
    fn require_acyclic(&self, parent: NodeId, child: NodeId) -> Result<(), TaffyError> {
        let target = taffy::NodeId::from(child);
        let mut cursor = Some(taffy::NodeId::from(parent));
        while let Some(node) = cursor {
            if node == target {
                return Err(TaffyError::InvalidChildNode);
            }
            cursor = self.tree.parent(node);
        }
        Ok(())
    }

    fn track(&mut self, id: taffy::NodeId) -> NodeId {
        let id = NodeId::from(id);
        self.live.insert(id.raw);
        id
    }
}

/// A tree of layout nodes. Safe to share between threads; calls are serialized internally.
#[export]
pub struct TaffyTree {
    inner: Mutex<Core>,
}

impl TaffyTree {
    /// Runs `f` under the lock. Panics inside Taffy are turned into an error instead of aborting the process.
    fn run<R>(&self, f: impl FnOnce(&mut Core) -> Result<R, TaffyError>) -> Result<R, TaffyError> {
        // The tree stays structurally valid after a panic, so recover from poisoning instead of failing forever.
        let mut core = self.inner.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        catch_unwind(AssertUnwindSafe(|| f(&mut core))).unwrap_or(Err(TaffyError::InvalidInputNode))
    }
}

impl Default for TaffyTree {
    fn default() -> Self {
        Self::new()
    }
}

fn to_taffy_ids(ids: &[NodeId]) -> Vec<taffy::NodeId> {
    ids.iter().copied().map(Into::into).collect()
}

#[export]
impl TaffyTree {
    /// Creates an empty tree with rounding enabled.
    pub fn new() -> Self {
        TaffyTree { inner: Mutex::new(Core { tree: Inner::new(), live: HashSet::new() }) }
    }

    /// Creates an empty tree with room for `capacity` nodes, so building a big tree does not reallocate.
    pub fn with_capacity(capacity: u32) -> Self {
        let capacity = capacity as usize;
        TaffyTree {
            inner: Mutex::new(Core { tree: Inner::with_capacity(capacity), live: HashSet::with_capacity(capacity) }),
        }
    }

    /// Rounds computed layouts to whole pixels (the default).
    pub fn enable_rounding(&self) {
        let _ = self.run(|c| {
            c.tree.enable_rounding();
            Ok(())
        });
    }

    /// Keeps fractional layout values.
    pub fn disable_rounding(&self) {
        let _ = self.run(|c| {
            c.tree.disable_rounding();
            Ok(())
        });
    }

    pub fn new_leaf(&self, style: Style) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            let id = c.tree.new_leaf(style.into())?;
            Ok(c.track(id))
        })
    }

    pub fn new_with_children(&self, style: Style, children: &[NodeId]) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            c.require_all(children, TaffyError::InvalidChildNode)?;
            let id = c.tree.new_with_children(style.into(), &to_taffy_ids(children))?;
            Ok(c.track(id))
        })
    }

    /// Removes every node.
    pub fn clear(&self) {
        let _ = self.run(|c| {
            c.tree.clear();
            c.live.clear();
            Ok(())
        });
    }

    /// Removes a node and detaches it from its parent. Its children become roots.
    pub fn remove(&self, node: NodeId) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            let removed = c.tree.remove(node.into())?;
            c.live.remove(&node.raw);
            Ok(removed.into())
        })
    }

    pub fn add_child(&self, parent: NodeId, child: NodeId) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            c.require(child, TaffyError::InvalidChildNode)?;
            c.require_acyclic(parent, child)?;
            Ok(c.tree.add_child(parent.into(), child.into())?)
        })
    }

    pub fn insert_child_at_index(&self, parent: NodeId, index: u32, child: NodeId) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            c.require(child, TaffyError::InvalidChildNode)?;
            c.require_acyclic(parent, child)?;
            Ok(c.tree.insert_child_at_index(parent.into(), index as usize, child.into())?)
        })
    }

    pub fn set_children(&self, parent: NodeId, children: &[NodeId]) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            c.require_all(children, TaffyError::InvalidChildNode)?;
            for child in children {
                c.require_acyclic(parent, *child)?;
            }
            Ok(c.tree.set_children(parent.into(), &to_taffy_ids(children))?)
        })
    }

    pub fn remove_child(&self, parent: NodeId, child: NodeId) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            c.require(child, TaffyError::InvalidChildNode)?;
            Ok(c.tree.remove_child(parent.into(), child.into())?.into())
        })
    }

    pub fn remove_child_at_index(&self, parent: NodeId, index: u32) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            Ok(c.tree.remove_child_at_index(parent.into(), index as usize)?.into())
        })
    }

    /// Replaces the child at `index`, returning the node that was replaced.
    pub fn replace_child_at_index(&self, parent: NodeId, index: u32, child: NodeId) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            c.require(child, TaffyError::InvalidChildNode)?;
            c.require_acyclic(parent, child)?;
            Ok(c.tree.replace_child_at_index(parent.into(), index as usize, child.into())?.into())
        })
    }

    pub fn child_at_index(&self, parent: NodeId, index: u32) -> Result<NodeId, TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            Ok(c.tree.child_at_index(parent.into(), index as usize)?.into())
        })
    }

    pub fn children(&self, parent: NodeId) -> Result<Vec<NodeId>, TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            Ok(c.tree.children(parent.into())?.into_iter().map(Into::into).collect())
        })
    }

    /// Detaches the children in `start..end` from `parent`. They stay in the tree as roots.
    pub fn remove_children_range(&self, parent: NodeId, start: u32, end: u32) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            // Taffy panics on an invalid range, so check it up front.
            let count = c.tree.children(parent.into())?.len();
            let (start, end) = (start as usize, end as usize);
            if start > end || end > count {
                return Err(TaffyError::ChildIndexOutOfBounds);
            }
            Ok(c.tree.remove_children_range(parent.into(), start..end)?)
        })
    }

    pub fn child_count(&self, parent: NodeId) -> Result<u32, TaffyError> {
        self.run(|c| {
            c.require(parent, TaffyError::InvalidParentNode)?;
            Ok(c.tree.children(parent.into())?.len() as u32)
        })
    }

    pub fn parent(&self, child: NodeId) -> Option<NodeId> {
        self.run(|c| {
            c.require(child, TaffyError::InvalidChildNode)?;
            Ok(c.tree.parent(child.into()).map(Into::into))
        })
        .unwrap_or(None)
    }

    /// Number of nodes in the tree.
    pub fn total_node_count(&self) -> u32 {
        self.run(|c| Ok(c.tree.total_node_count() as u32)).unwrap_or(0)
    }

    pub fn set_style(&self, node: NodeId, style: Style) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(c.tree.set_style(node.into(), style.into())?)
        })
    }

    pub fn style(&self, node: NodeId) -> Result<Style, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(c.tree.style(node.into())?.clone().into())
        })
    }

    /// Marks a node (and its ancestors) as needing layout.
    pub fn mark_dirty(&self, node: NodeId) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(c.tree.mark_dirty(node.into())?)
        })
    }

    pub fn dirty(&self, node: NodeId) -> Result<bool, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(c.tree.dirty(node.into())?)
        })
    }

    /// The final (rounded, if rounding is enabled) layout of a node.
    pub fn layout(&self, node: NodeId) -> Result<NodeLayout, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(NodeLayout::from(c.tree.layout(node.into())?))
        })
    }

    /// The absolute and fixed boxes that `node` is the containing block of, as of the last layout. `node` lays them
    /// out instead of their parent, and their location is relative to `node`.
    pub fn hoisted_children(&self, node: NodeId) -> Result<Vec<NodeId>, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(c.tree.hoisted_children(node.into())?.iter().copied().map(Into::into).collect())
        })
    }

    /// The tracks and item placement a grid container resolved to in the last layout, or `None` if `node` is not a
    /// grid container or has not been laid out.
    pub fn grid_layout_info(&self, node: NodeId) -> Result<Option<GridLayoutInfo>, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(match c.tree.detailed_layout_info(node.into()) {
                taffy::DetailedLayoutInfo::Grid(info) => Some(GridLayoutInfo::from(&**info)),
                _ => None,
            })
        })
    }

    /// The layout before rounding.
    pub fn unrounded_layout(&self, node: NodeId) -> Result<NodeLayout, TaffyError> {
        self.run(|c| {
            c.require(node, TaffyError::InvalidInputNode)?;
            Ok(NodeLayout::from(c.tree.unrounded_layout(node.into())))
        })
    }

    /// Computes the layout of the subtree under `root`. Leaves are sized by their style only.
    pub fn compute_layout(&self, root: NodeId, available: AvailableSize) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(root, TaffyError::InvalidInputNode)?;
            Ok(c.tree.compute_layout(root.into(), available.into())?)
        })
    }

    /// Computes the layout of the subtree under `root`, asking `measure` for leaf content sizes.
    pub fn compute_layout_with_measure(
        &self,
        root: NodeId,
        available: AvailableSize,
        measure: Box<dyn Measure>,
    ) -> Result<(), TaffyError> {
        self.run(|c| {
            c.require(root, TaffyError::InvalidInputNode)?;
            c.tree.compute_layout_with_measure(root.into(), available.into(), |inputs, node, _ctx, style| {
                compute_leaf_layout(
                    inputs,
                    style,
                    |_, _| 0.0,
                    |known, available| measure.measure(node.into(), known.into(), available.into()).into(),
                )
            })?;
            Ok(())
        })
    }

    /// Computes the layout of the subtree under `root`, asking `measure` for leaf content sizes.
    ///
    /// Unlike [`compute_layout_with_measure`](Self::compute_layout_with_measure), `measure` may
    /// suspend. Layout is recomputed until it no longer needs new measurements, so `measure` can
    /// be called for sizes that end up unused, and must return the same answer for the same input.
    pub async fn compute_layout_with_async_measure(
        &self,
        root: NodeId,
        available: AvailableSize,
        measure: Arc<dyn AsyncMeasure>,
    ) -> Result<(), TaffyError> {
        let mut answers: HashMap<MeasureKey, taffy::geometry::Size<f32>> = HashMap::new();

        for _ in 0..MAX_ASYNC_PASSES {
            let questions = self.run(|c| {
                c.require(root, TaffyError::InvalidInputNode)?;
                let mut asked: HashSet<MeasureKey> = HashSet::new();
                let mut questions: Vec<(MeasureKey, MeasureQuestion)> = Vec::new();

                c.tree.compute_layout_with_measure(root.into(), available.into(), |inputs, node, _ctx, style| {
                    compute_leaf_layout(
                        inputs,
                        style,
                        |_, _| 0.0,
                        |known, available| {
                            let key: MeasureKey = (
                                NodeId::from(node).raw,
                                [known.width.map(f32::to_bits), known.height.map(f32::to_bits)],
                                [space_key(available.width), space_key(available.height)],
                            );
                            if let Some(size) = answers.get(&key) {
                                return *size;
                            }
                            if asked.insert(key) {
                                questions.push((
                                    key,
                                    MeasureQuestion {
                                        node: node.into(),
                                        known: known.into(),
                                        available: available.into(),
                                    },
                                ));
                            }
                            // Placeholder; the layout is redone once the real answer is known.
                            taffy::geometry::Size::ZERO
                        },
                    )
                })?;

                // Layouts computed from placeholders must not be served from Taffy's cache next pass.
                for (_, question) in &questions {
                    c.tree.mark_dirty(question.node.into())?;
                }
                Ok(questions)
            })?;

            if questions.is_empty() {
                return Ok(());
            }
            for (key, question) in questions {
                let size = measure.measure(question.node, question.known, question.available).await;
                answers.insert(key, size.into());
            }
        }
        Err(TaffyError::MeasureDidNotConverge)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::AvailableSpace;
    use crate::grid::{GridTemplateComponent, MaxTrackSizingFunction, MinTrackSizingFunction, TrackPosition, TrackSizingFunction};
    use crate::style::{Display, FlexDirection, LengthPercentageAuto, Overflow, Position, TaffyDimension};

    fn px(v: f32) -> TaffyDimension {
        TaffyDimension::Length(v)
    }

    fn fixed_size(width: f32, height: f32) -> crate::style::DimensionSize {
        crate::style::DimensionSize { width: px(width), height: px(height) }
    }

    fn max_content() -> AvailableSize {
        AvailableSize { width: AvailableSpace::MaxContent, height: AvailableSpace::MaxContent }
    }

    /// A 100x100 scroll container holding two 100x80 items.
    fn scroll_container(direction: FlexDirection) -> (TaffyTree, NodeId) {
        let tree = TaffyTree::new();
        let item_style = Style { size: fixed_size(100.0, 80.0), flex_shrink: 0.0, ..Style::default() };
        let a = tree.new_leaf(item_style.clone()).unwrap();
        let b = tree.new_leaf(item_style).unwrap();
        let root_style = Style {
            display: Display::Flex,
            flex_direction: direction,
            overflow: crate::style::OverflowPoint { x: Overflow::Scroll, y: Overflow::Scroll },
            size: fixed_size(100.0, 100.0),
            ..Style::default()
        };
        let root = tree.new_with_children(root_style, &[a, b]).unwrap();
        tree.compute_layout(root, max_content()).unwrap();
        (tree, root)
    }

    #[test]
    fn scroll_origin_follows_the_flex_direction() {
        let (tree, root) = scroll_container(FlexDirection::Column);
        let layout = tree.layout(root).unwrap();
        assert_eq!(layout.scroll_origin_reversed, AxisFlags { x: false, y: false });

        let (tree, root) = scroll_container(FlexDirection::ColumnReverse);
        let layout = tree.layout(root).unwrap();
        assert_eq!(layout.scroll_origin_reversed, AxisFlags { x: false, y: true });

        let (tree, root) = scroll_container(FlexDirection::RowReverse);
        let layout = tree.layout(root).unwrap();
        assert_eq!(layout.scroll_origin_reversed, AxisFlags { x: true, y: false });
    }

    #[test]
    fn scroll_extent_is_the_overflow_beyond_the_padding_box() {
        // Two 80pt items in a 100pt column: 60pt of content is out of view, in both directions of travel.
        for direction in [FlexDirection::Column, FlexDirection::ColumnReverse] {
            let (tree, root) = scroll_container(direction);
            let layout = tree.layout(root).unwrap();
            assert_eq!(layout.scroll_height, 60.0, "{direction:?}");
            assert_eq!(layout.scroll_width, 0.0, "{direction:?}");
        }
    }

    #[test]
    fn ordinary_nodes_do_not_scroll() {
        let tree = TaffyTree::new();
        let leaf = tree.new_leaf(Style { size: fixed_size(10.0, 10.0), ..Style::default() }).unwrap();
        tree.compute_layout(leaf, max_content()).unwrap();
        let layout = tree.layout(leaf).unwrap();
        assert_eq!(layout.scroll_origin_reversed, AxisFlags { x: false, y: false });
        assert_eq!((layout.scroll_width, layout.scroll_height), (0.0, 0.0));
    }

    #[test]
    fn grid_info_reports_tracks_and_placement() {
        let tree = TaffyTree::new();
        let a = tree.new_leaf(Style::default()).unwrap();
        let b = tree.new_leaf(Style::default()).unwrap();
        let track = |v: f32| {
            GridTemplateComponent::Single(TrackSizingFunction {
                min: MinTrackSizingFunction::Length(v),
                max: MaxTrackSizingFunction::Length(v),
            })
        };
        let root_style = Style {
            display: Display::Grid,
            size: fixed_size(100.0, 50.0),
            grid_template_columns: vec![track(30.0), track(70.0)],
            grid_template_rows: vec![track(50.0)],
            ..Style::default()
        };
        let root = tree.new_with_children(root_style, &[a, b]).unwrap();

        // Nothing has been laid out yet.
        assert_eq!(tree.grid_layout_info(root).unwrap(), None);
        tree.compute_layout(root, max_content()).unwrap();

        let info = tree.grid_layout_info(root).unwrap().expect("a grid container");
        assert_eq!(info.columns.explicit_tracks, 2);
        assert_eq!(
            info.columns.positions,
            vec![TrackPosition { start: 0.0, end: 30.0 }, TrackPosition { start: 30.0, end: 100.0 }]
        );
        assert_eq!(info.rows.positions, vec![TrackPosition { start: 0.0, end: 50.0 }]);
        assert_eq!(info.items.len(), 2);
        assert_eq!((info.items[1].column_start, info.items[1].column_end), (2, 3));
        // Leaves are not grid containers.
        assert_eq!(tree.grid_layout_info(a).unwrap(), None);
    }

    #[test]
    fn hoisted_children_are_the_absolute_boxes_laid_out_by_a_container() {
        let tree = TaffyTree::new();
        let flow = tree.new_leaf(Style { size: fixed_size(10.0, 10.0), ..Style::default() }).unwrap();
        let overlay = tree
            .new_leaf(Style {
                position: Position::Absolute,
                size: fixed_size(5.0, 5.0),
                inset: crate::style::LengthPercentageAutoRect {
                    left: LengthPercentageAuto::Length(2.0),
                    right: LengthPercentageAuto::Auto,
                    top: LengthPercentageAuto::Length(3.0),
                    bottom: LengthPercentageAuto::Auto,
                },
                ..Style::default()
            })
            .unwrap();
        // Only a positioned container is the containing block of absolute boxes.
        let root = tree
            .new_with_children(
                Style { position: Position::Relative, size: fixed_size(50.0, 50.0), ..Style::default() },
                &[flow, overlay],
            )
            .unwrap();
        tree.compute_layout(root, max_content()).unwrap();

        assert_eq!(tree.hoisted_children(root).unwrap(), vec![overlay]);
        assert_eq!(tree.layout(overlay).unwrap().location, Point { x: 2.0, y: 3.0 });
        assert!(tree.hoisted_children(flow).unwrap().is_empty());
    }

    #[test]
    fn remove_children_range_detaches_and_validates() {
        let tree = TaffyTree::with_capacity(8);
        let kids: Vec<_> = (0..4).map(|_| tree.new_leaf(Style::default()).unwrap()).collect();
        let root = tree.new_with_children(Style::default(), &kids).unwrap();

        tree.remove_children_range(root, 1, 3).unwrap();
        assert_eq!(tree.children(root).unwrap(), vec![kids[0], kids[3]]);
        assert_eq!(tree.parent(kids[1]), None);
        // Detached nodes stay in the tree.
        assert_eq!(tree.total_node_count(), 5);

        // An invalid range is an error, not a panic across the FFI boundary.
        assert_eq!(tree.remove_children_range(root, 1, 9), Err(TaffyError::ChildIndexOutOfBounds));
        assert_eq!(tree.remove_children_range(root, 2, 1), Err(TaffyError::ChildIndexOutOfBounds));
        assert_eq!(tree.children(root).unwrap().len(), 2);
    }

    #[test]
    fn balanced_wrapping_honours_the_minimum_line_count() {
        // Four 10pt items fit one 100pt line; asking for at least two lines must split them.
        let lines_used = |flex_line_count: u16| {
            let tree = TaffyTree::new();
            let item = Style { size: fixed_size(10.0, 10.0), flex_shrink: 0.0, ..Style::default() };
            let kids: Vec<_> = (0..4).map(|_| tree.new_leaf(item.clone()).unwrap()).collect();
            let root_style = Style {
                display: Display::Flex,
                flex_wrap: crate::style::FlexWrap::Balance,
                flex_line_count,
                size: fixed_size(100.0, 100.0),
                ..Style::default()
            };
            let root = tree.new_with_children(root_style, &kids).unwrap();
            tree.compute_layout(root, max_content()).unwrap();
            let mut ys: Vec<u32> = kids.iter().map(|k| tree.layout(*k).unwrap().location.y as u32).collect();
            ys.dedup();
            ys.len()
        };
        assert_eq!(lines_used(1), 1);
        assert_eq!(lines_used(2), 2);
    }
}
