//! The exported `TaffyTree` handle and the measure callback.

use std::collections::{HashMap, HashSet};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, Mutex};

use boltffi::*;
use taffy::{compute_leaf_layout, TaffyTree as Inner};

use crate::geometry::{AvailableSize, NodeId, OptionalSize, Point, Rect, Size};
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
    pub scrollable_overflow_rect: Rect,
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
            scrollable_overflow_rect: l.scrollable_overflow_rect.into(),
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
const MAX_ASYNC_PASSES: usize = 64;

/// Identifies one measure question; floats are compared bit-for-bit.
type MeasureKey = (u64, [Option<u32>; 2], [(u8, u32); 2]);

fn space_key(space: taffy::AvailableSpace) -> (u8, u32) {
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
