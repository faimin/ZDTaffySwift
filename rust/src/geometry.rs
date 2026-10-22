//! Plain geometry records shared by styles, layouts and the measure callback.
//!
//! BoltFFI cannot export generic structs, so every `Size<T>` / `Rect<T>` / `Point<T>`
//! instantiation Taffy uses gets its own concrete record here.

use boltffi::*;
use taffy::geometry as t;

/// Identifies a node inside a [`TaffyTree`](crate::TaffyTree).
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct NodeId {
    pub raw: u64,
}

impl From<taffy::NodeId> for NodeId {
    fn from(id: taffy::NodeId) -> Self {
        NodeId { raw: id.into() }
    }
}

impl From<NodeId> for taffy::NodeId {
    fn from(id: NodeId) -> Self {
        taffy::NodeId::from(id.raw)
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Size {
    pub width: f32,
    pub height: f32,
}

impl From<t::Size<f32>> for Size {
    fn from(v: t::Size<f32>) -> Self {
        Size { width: v.width, height: v.height }
    }
}

impl From<Size> for t::Size<f32> {
    fn from(v: Size) -> Self {
        t::Size { width: v.width, height: v.height }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl From<t::Point<f32>> for Point {
    fn from(v: t::Point<f32>) -> Self {
        Point { x: v.x, y: v.y }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect {
    pub left: f32,
    pub right: f32,
    pub top: f32,
    pub bottom: f32,
}

impl From<t::Rect<f32>> for Rect {
    fn from(v: t::Rect<f32>) -> Self {
        Rect { left: v.left, right: v.right, top: v.top, bottom: v.bottom }
    }
}

/// A size whose axes may be unknown (`nil` in Swift).
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OptionalSize {
    pub width: Option<f32>,
    pub height: Option<f32>,
}

impl From<t::Size<Option<f32>>> for OptionalSize {
    fn from(v: t::Size<Option<f32>>) -> Self {
        OptionalSize { width: v.width, height: v.height }
    }
}

/// The space offered to a node along one axis.
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum AvailableSpace {
    Definite(f32),
    MinContent,
    MaxContent,
}

impl From<taffy::AvailableSpace> for AvailableSpace {
    fn from(v: taffy::AvailableSpace) -> Self {
        match v {
            taffy::AvailableSpace::Definite(x) => AvailableSpace::Definite(x),
            taffy::AvailableSpace::MinContent => AvailableSpace::MinContent,
            taffy::AvailableSpace::MaxContent => AvailableSpace::MaxContent,
        }
    }
}

impl From<AvailableSpace> for taffy::AvailableSpace {
    fn from(v: AvailableSpace) -> Self {
        match v {
            AvailableSpace::Definite(x) => taffy::AvailableSpace::Definite(x),
            AvailableSpace::MinContent => taffy::AvailableSpace::MinContent,
            AvailableSpace::MaxContent => taffy::AvailableSpace::MaxContent,
        }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct AvailableSize {
    pub width: AvailableSpace,
    pub height: AvailableSpace,
}

impl From<t::Size<taffy::AvailableSpace>> for AvailableSize {
    fn from(v: t::Size<taffy::AvailableSpace>) -> Self {
        AvailableSize { width: v.width.into(), height: v.height.into() }
    }
}

impl From<AvailableSize> for t::Size<taffy::AvailableSpace> {
    fn from(v: AvailableSize) -> Self {
        t::Size { width: v.width.into(), height: v.height.into() }
    }
}
