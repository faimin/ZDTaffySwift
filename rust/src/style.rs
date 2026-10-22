//! Mirrors of Taffy's `Style` and the value types it is built from.
//!
//! Taffy's own types cannot carry BoltFFI attributes, so each one is redefined here with
//! the same variants and field names, plus `From` conversions in both directions.
//! Names that would collide with Foundation / SwiftUI (`Dimension`, `Layout`) carry a
//! `Taffy` prefix.

use boltffi::*;
use taffy::geometry as g;
use taffy::style as t;

use crate::grid::{
    GridAutoFlow, GridPlacementLine, GridTemplateAreas, GridTemplateComponent, TrackSizingFunction,
};

/// Implements `From` in both directions between a fieldless mirror enum and its Taffy twin.
macro_rules! mirror_enum {
    ($mirror:ident <=> $taffy:path { $($variant:ident),+ $(,)? }) => {
        impl From<$taffy> for $mirror {
            fn from(v: $taffy) -> Self {
                match v { $(<$taffy>::$variant => $mirror::$variant,)+ }
            }
        }
        impl From<$mirror> for $taffy {
            fn from(v: $mirror) -> Self {
                match v { $($mirror::$variant => <$taffy>::$variant,)+ }
            }
        }
    };
}

pub(crate) use mirror_enum;

// ---------------------------------------------------------------------------------------
// Keyword enums
// ---------------------------------------------------------------------------------------

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Display {
    Block,
    FlowRoot,
    Flex,
    Grid,
    None,
}
mirror_enum!(Display <=> t::Display { Block, FlowRoot, Flex, Grid, None });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Position {
    Static,
    Relative,
    Absolute,
    Fixed,
    Sticky,
}
mirror_enum!(Position <=> t::Position { Static, Relative, Absolute, Fixed, Sticky });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Overflow {
    Visible,
    Clip,
    Hidden,
    Scroll,
}
mirror_enum!(Overflow <=> t::Overflow { Visible, Clip, Hidden, Scroll });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BoxSizing {
    BorderBox,
    ContentBox,
}
mirror_enum!(BoxSizing <=> t::BoxSizing { BorderBox, ContentBox });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    Ltr,
    Rtl,
}
mirror_enum!(Direction <=> t::Direction { Ltr, Rtl });

/// Taffy's `Float` (named differently to avoid clashing with Swift's `Float`).
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FloatSide {
    Left,
    Right,
    None,
}
mirror_enum!(FloatSide <=> t::Float { Left, Right, None });

/// Taffy's `Clear`.
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClearSide {
    Left,
    Right,
    Both,
    None,
}
mirror_enum!(ClearSide <=> t::Clear { Left, Right, Both, None });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TextAlign {
    Auto,
    LegacyLeft,
    LegacyRight,
    LegacyCenter,
}
mirror_enum!(TextAlign <=> t::TextAlign { Auto, LegacyLeft, LegacyRight, LegacyCenter });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlexDirection {
    Row,
    Column,
    RowReverse,
    ColumnReverse,
}
mirror_enum!(FlexDirection <=> t::FlexDirection { Row, Column, RowReverse, ColumnReverse });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlexWrap {
    NoWrap,
    Wrap,
    WrapReverse,
    Balance,
    BalanceReverse,
}
mirror_enum!(FlexWrap <=> t::FlexWrap { NoWrap, Wrap, WrapReverse, Balance, BalanceReverse });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AlignmentSafety {
    Default,
    Unsafe,
    Safe,
}
mirror_enum!(AlignmentSafety <=> t::AlignmentSafety { Default, Unsafe, Safe });

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AlignItemsKeyword {
    Normal,
    Start,
    End,
    FlexStart,
    FlexEnd,
    SelfStart,
    SelfEnd,
    Center,
    Baseline,
    Stretch,
}
mirror_enum!(AlignItemsKeyword <=> t::AlignItemsKeyword {
    Normal, Start, End, FlexStart, FlexEnd, SelfStart, SelfEnd, Center, Baseline, Stretch
});

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AlignContentKeyword {
    Normal,
    Start,
    End,
    FlexStart,
    FlexEnd,
    Center,
    Stretch,
    SpaceBetween,
    SpaceEvenly,
    SpaceAround,
}
mirror_enum!(AlignContentKeyword <=> t::AlignContentKeyword {
    Normal, Start, End, FlexStart, FlexEnd, Center, Stretch, SpaceBetween, SpaceEvenly, SpaceAround
});

/// Used for `align-items`, `justify-items`, `align-self` and `justify-self`.
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AlignItems {
    pub keyword: AlignItemsKeyword,
    pub safety: AlignmentSafety,
}

impl From<t::AlignItems> for AlignItems {
    fn from(v: t::AlignItems) -> Self {
        AlignItems { keyword: v.keyword.into(), safety: v.safety.into() }
    }
}

impl From<AlignItems> for t::AlignItems {
    fn from(v: AlignItems) -> Self {
        t::AlignItems { keyword: v.keyword.into(), safety: v.safety.into() }
    }
}

/// Used for `align-content` and `justify-content`.
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AlignContent {
    pub keyword: AlignContentKeyword,
    pub safety: AlignmentSafety,
}

impl From<t::AlignContent> for AlignContent {
    fn from(v: t::AlignContent) -> Self {
        AlignContent { keyword: v.keyword.into(), safety: v.safety.into() }
    }
}

impl From<AlignContent> for t::AlignContent {
    fn from(v: AlignContent) -> Self {
        t::AlignContent { keyword: v.keyword.into(), safety: v.safety.into() }
    }
}

/// CSS `contain` (only the flags Taffy understands).
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Contain {
    pub layout: bool,
    pub paint: bool,
}

impl From<t::Contain> for Contain {
    fn from(v: t::Contain) -> Self {
        Contain { layout: v.contains(t::Contain::LAYOUT), paint: v.contains(t::Contain::PAINT) }
    }
}

impl From<Contain> for t::Contain {
    fn from(v: Contain) -> Self {
        let mut out = t::Contain::NONE;
        if v.layout {
            out = out.union(t::Contain::LAYOUT);
        }
        if v.paint {
            out = out.union(t::Contain::PAINT);
        }
        out
    }
}

// ---------------------------------------------------------------------------------------
// Length-like values
// ---------------------------------------------------------------------------------------

/// A length or a percentage (never `auto`). `calc()` is not supported.
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum LengthPercentage {
    Length(f32),
    Percent(f32),
}

impl From<t::LengthPercentage> for LengthPercentage {
    fn from(v: t::LengthPercentage) -> Self {
        match v.expand() {
            t::ExpandedLengthPercentage::Percent(x) => LengthPercentage::Percent(x),
            t::ExpandedLengthPercentage::Length(x) => LengthPercentage::Length(x),
            // `calc()` values can only be created through the unsafe raw API, which this crate never exposes.
            _ => LengthPercentage::Length(0.0),
        }
    }
}

impl From<LengthPercentage> for t::LengthPercentage {
    fn from(v: LengthPercentage) -> Self {
        match v {
            LengthPercentage::Length(x) => t::LengthPercentage::length(x),
            LengthPercentage::Percent(x) => t::LengthPercentage::percent(x),
        }
    }
}

/// A length, a percentage or `auto`.
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum LengthPercentageAuto {
    Length(f32),
    Percent(f32),
    Auto,
}

impl From<t::LengthPercentageAuto> for LengthPercentageAuto {
    fn from(v: t::LengthPercentageAuto) -> Self {
        match v.expand() {
            t::ExpandedLengthPercentageAuto::Length(x) => LengthPercentageAuto::Length(x),
            t::ExpandedLengthPercentageAuto::Percent(x) => LengthPercentageAuto::Percent(x),
            _ => LengthPercentageAuto::Auto,
        }
    }
}

impl From<LengthPercentageAuto> for t::LengthPercentageAuto {
    fn from(v: LengthPercentageAuto) -> Self {
        match v {
            LengthPercentageAuto::Length(x) => t::LengthPercentageAuto::length(x),
            LengthPercentageAuto::Percent(x) => t::LengthPercentageAuto::percent(x),
            LengthPercentageAuto::Auto => t::LengthPercentageAuto::auto(),
        }
    }
}

/// A preferred size: a length, a percentage, `auto` or a sizing keyword.
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TaffyDimension {
    Length(f32),
    Percent(f32),
    Auto,
    MinContent,
    MaxContent,
    FitContentPx(f32),
    FitContentPercent(f32),
    FitContent,
    Stretch,
    Content,
}

impl From<t::Dimension> for TaffyDimension {
    fn from(v: t::Dimension) -> Self {
        use t::ExpandedDimension as E;
        match v.expand() {
            E::Length(x) => TaffyDimension::Length(x),
            E::Percent(x) => TaffyDimension::Percent(x),
            E::Auto => TaffyDimension::Auto,
            E::MinContent => TaffyDimension::MinContent,
            E::MaxContent => TaffyDimension::MaxContent,
            E::FitContentPx(x) => TaffyDimension::FitContentPx(x),
            E::FitContentPercent(x) => TaffyDimension::FitContentPercent(x),
            E::FitContent => TaffyDimension::FitContent,
            E::Stretch => TaffyDimension::Stretch,
            E::Content => TaffyDimension::Content,
            // `calc()` values can only be created through the unsafe raw API, which this crate never exposes.
            _ => TaffyDimension::Auto,
        }
    }
}

impl From<TaffyDimension> for t::Dimension {
    fn from(v: TaffyDimension) -> Self {
        match v {
            TaffyDimension::Length(x) => t::Dimension::length(x),
            TaffyDimension::Percent(x) => t::Dimension::percent(x),
            TaffyDimension::Auto => t::Dimension::auto(),
            TaffyDimension::MinContent => t::Dimension::min_content(),
            TaffyDimension::MaxContent => t::Dimension::max_content(),
            TaffyDimension::FitContentPx(x) => t::Dimension::fit_content_px(x),
            TaffyDimension::FitContentPercent(x) => t::Dimension::fit_content_percent(x),
            TaffyDimension::FitContent => t::Dimension::fit_content(),
            TaffyDimension::Stretch => t::Dimension::stretch(),
            TaffyDimension::Content => t::Dimension::content(),
        }
    }
}

// ---------------------------------------------------------------------------------------
// Concrete instantiations of Taffy's generic Size / Rect / Point
// ---------------------------------------------------------------------------------------

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct DimensionSize {
    pub width: TaffyDimension,
    pub height: TaffyDimension,
}

impl From<g::Size<t::Dimension>> for DimensionSize {
    fn from(v: g::Size<t::Dimension>) -> Self {
        DimensionSize { width: v.width.into(), height: v.height.into() }
    }
}

impl From<DimensionSize> for g::Size<t::Dimension> {
    fn from(v: DimensionSize) -> Self {
        g::Size { width: v.width.into(), height: v.height.into() }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LengthPercentageAutoSize {
    pub width: LengthPercentageAuto,
    pub height: LengthPercentageAuto,
}

impl From<g::Size<t::LengthPercentageAuto>> for LengthPercentageAutoSize {
    fn from(v: g::Size<t::LengthPercentageAuto>) -> Self {
        LengthPercentageAutoSize { width: v.width.into(), height: v.height.into() }
    }
}

impl From<LengthPercentageAutoSize> for g::Size<t::LengthPercentageAuto> {
    fn from(v: LengthPercentageAutoSize) -> Self {
        g::Size { width: v.width.into(), height: v.height.into() }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LengthPercentageSize {
    pub width: LengthPercentage,
    pub height: LengthPercentage,
}

impl From<g::Size<t::LengthPercentage>> for LengthPercentageSize {
    fn from(v: g::Size<t::LengthPercentage>) -> Self {
        LengthPercentageSize { width: v.width.into(), height: v.height.into() }
    }
}

impl From<LengthPercentageSize> for g::Size<t::LengthPercentage> {
    fn from(v: LengthPercentageSize) -> Self {
        g::Size { width: v.width.into(), height: v.height.into() }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LengthPercentageAutoRect {
    pub left: LengthPercentageAuto,
    pub right: LengthPercentageAuto,
    pub top: LengthPercentageAuto,
    pub bottom: LengthPercentageAuto,
}

impl From<g::Rect<t::LengthPercentageAuto>> for LengthPercentageAutoRect {
    fn from(v: g::Rect<t::LengthPercentageAuto>) -> Self {
        LengthPercentageAutoRect {
            left: v.left.into(),
            right: v.right.into(),
            top: v.top.into(),
            bottom: v.bottom.into(),
        }
    }
}

impl From<LengthPercentageAutoRect> for g::Rect<t::LengthPercentageAuto> {
    fn from(v: LengthPercentageAutoRect) -> Self {
        g::Rect { left: v.left.into(), right: v.right.into(), top: v.top.into(), bottom: v.bottom.into() }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LengthPercentageRect {
    pub left: LengthPercentage,
    pub right: LengthPercentage,
    pub top: LengthPercentage,
    pub bottom: LengthPercentage,
}

impl From<g::Rect<t::LengthPercentage>> for LengthPercentageRect {
    fn from(v: g::Rect<t::LengthPercentage>) -> Self {
        LengthPercentageRect {
            left: v.left.into(),
            right: v.right.into(),
            top: v.top.into(),
            bottom: v.bottom.into(),
        }
    }
}

impl From<LengthPercentageRect> for g::Rect<t::LengthPercentage> {
    fn from(v: LengthPercentageRect) -> Self {
        g::Rect { left: v.left.into(), right: v.right.into(), top: v.top.into(), bottom: v.bottom.into() }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OverflowPoint {
    pub x: Overflow,
    pub y: Overflow,
}

impl From<g::Point<t::Overflow>> for OverflowPoint {
    fn from(v: g::Point<t::Overflow>) -> Self {
        OverflowPoint { x: v.x.into(), y: v.y.into() }
    }
}

impl From<OverflowPoint> for g::Point<t::Overflow> {
    fn from(v: OverflowPoint) -> Self {
        g::Point { x: v.x.into(), y: v.y.into() }
    }
}

// ---------------------------------------------------------------------------------------
// Style
// ---------------------------------------------------------------------------------------

/// The complete set of layout properties of a node.
///
/// Mirrors `taffy::Style`; `Style::default()` equals `taffy::Style::DEFAULT`.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct Style {
    pub display: Display,
    pub item_is_table: bool,
    pub item_is_replaced: bool,
    pub item_is_compressible_replaced: bool,
    pub box_sizing: BoxSizing,
    pub direction: Direction,
    pub overflow: OverflowPoint,
    pub scrollbar_width: f32,
    pub contain: Contain,
    pub float: FloatSide,
    pub clear: ClearSide,
    pub position: Position,
    pub inset: LengthPercentageAutoRect,
    pub size: DimensionSize,
    pub min_size: LengthPercentageAutoSize,
    pub max_size: LengthPercentageAutoSize,
    pub aspect_ratio: Option<f32>,
    pub margin: LengthPercentageAutoRect,
    pub padding: LengthPercentageRect,
    pub border: LengthPercentageRect,
    pub align_items: AlignItems,
    pub align_self: Option<AlignItems>,
    pub justify_items: AlignItems,
    pub justify_self: Option<AlignItems>,
    pub align_content: AlignContent,
    pub justify_content: AlignContent,
    pub gap: LengthPercentageSize,
    pub text_align: TextAlign,
    pub flex_direction: FlexDirection,
    pub flex_wrap: FlexWrap,
    pub flex_basis: TaffyDimension,
    pub flex_grow: f32,
    pub flex_shrink: f32,
    pub grid_template_rows: Vec<GridTemplateComponent>,
    pub grid_template_columns: Vec<GridTemplateComponent>,
    pub grid_auto_rows: Vec<TrackSizingFunction>,
    pub grid_auto_columns: Vec<TrackSizingFunction>,
    pub grid_auto_flow: GridAutoFlow,
    pub grid_template_areas: Option<GridTemplateAreas>,
    /// Line names for `grid_template_columns`, one list per line.
    pub grid_template_column_names: Vec<Vec<String>>,
    /// Line names for `grid_template_rows`, one list per line.
    pub grid_template_row_names: Vec<Vec<String>>,
    pub grid_row: GridPlacementLine,
    pub grid_column: GridPlacementLine,
}

impl Default for Style {
    fn default() -> Self {
        taffy::Style::DEFAULT.into()
    }
}

impl From<taffy::Style> for Style {
    fn from(s: taffy::Style) -> Self {
        Style {
            display: s.display.into(),
            item_is_table: s.item_is_table,
            item_is_replaced: s.item_is_replaced,
            item_is_compressible_replaced: s.item_is_compressible_replaced,
            box_sizing: s.box_sizing.into(),
            direction: s.direction.into(),
            overflow: s.overflow.into(),
            scrollbar_width: s.scrollbar_width,
            contain: s.contain.into(),
            float: s.float.into(),
            clear: s.clear.into(),
            position: s.position.into(),
            inset: s.inset.into(),
            size: s.size.into(),
            min_size: s.min_size.into(),
            max_size: s.max_size.into(),
            aspect_ratio: s.aspect_ratio,
            margin: s.margin.into(),
            padding: s.padding.into(),
            border: s.border.into(),
            align_items: s.align_items.into(),
            align_self: s.align_self.map(Into::into),
            justify_items: s.justify_items.into(),
            justify_self: s.justify_self.map(Into::into),
            align_content: s.align_content.into(),
            justify_content: s.justify_content.into(),
            gap: s.gap.into(),
            text_align: s.text_align.into(),
            flex_direction: s.flex_direction.into(),
            flex_wrap: s.flex_wrap.into(),
            flex_basis: s.flex_basis.into(),
            flex_grow: s.flex_grow,
            flex_shrink: s.flex_shrink,
            grid_template_rows: s.grid_template_rows.into_iter().map(Into::into).collect(),
            grid_template_columns: s.grid_template_columns.into_iter().map(Into::into).collect(),
            grid_auto_rows: s.grid_auto_rows.into_iter().map(Into::into).collect(),
            grid_auto_columns: s.grid_auto_columns.into_iter().map(Into::into).collect(),
            grid_auto_flow: s.grid_auto_flow.into(),
            grid_template_areas: s.grid_template_areas.map(Into::into),
            grid_template_column_names: s.grid_template_column_names.into_iter().map(|l| l.into_iter().collect()).collect(),
            grid_template_row_names: s.grid_template_row_names.into_iter().map(|l| l.into_iter().collect()).collect(),
            grid_row: s.grid_row.into(),
            grid_column: s.grid_column.into(),
        }
    }
}

impl From<Style> for taffy::Style {
    fn from(s: Style) -> Self {
        taffy::Style {
            display: s.display.into(),
            item_is_table: s.item_is_table,
            item_is_replaced: s.item_is_replaced,
            item_is_compressible_replaced: s.item_is_compressible_replaced,
            box_sizing: s.box_sizing.into(),
            direction: s.direction.into(),
            overflow: s.overflow.into(),
            scrollbar_width: s.scrollbar_width,
            contain: s.contain.into(),
            float: s.float.into(),
            clear: s.clear.into(),
            position: s.position.into(),
            inset: s.inset.into(),
            size: s.size.into(),
            min_size: s.min_size.into(),
            max_size: s.max_size.into(),
            aspect_ratio: s.aspect_ratio,
            margin: s.margin.into(),
            padding: s.padding.into(),
            border: s.border.into(),
            align_items: s.align_items.into(),
            align_self: s.align_self.map(Into::into),
            justify_items: s.justify_items.into(),
            justify_self: s.justify_self.map(Into::into),
            align_content: s.align_content.into(),
            justify_content: s.justify_content.into(),
            gap: s.gap.into(),
            text_align: s.text_align.into(),
            flex_direction: s.flex_direction.into(),
            flex_wrap: s.flex_wrap.into(),
            flex_basis: s.flex_basis.into(),
            flex_grow: s.flex_grow,
            flex_shrink: s.flex_shrink,
            grid_template_rows: s.grid_template_rows.into_iter().map(Into::into).collect(),
            grid_template_columns: s.grid_template_columns.into_iter().map(Into::into).collect(),
            grid_auto_rows: s.grid_auto_rows.into_iter().map(Into::into).collect(),
            grid_auto_columns: s.grid_auto_columns.into_iter().map(Into::into).collect(),
            grid_auto_flow: s.grid_auto_flow.into(),
            grid_template_areas: s.grid_template_areas.map(Into::into),
            grid_template_column_names: s.grid_template_column_names.into_iter().map(|l| l.into_iter().collect()).collect(),
            grid_template_row_names: s.grid_template_row_names.into_iter().map(|l| l.into_iter().collect()).collect(),
            grid_row: s.grid_row.into(),
            grid_column: s.grid_column.into(),
            ..taffy::Style::DEFAULT
        }
    }
}

/// `taffy::Style::DEFAULT`; backs `Style()` on the Swift side.
#[export]
pub fn default_style() -> Style {
    Style::default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::*;

    #[test]
    fn default_style_matches_taffy() {
        let mirrored = Style::default();
        let back: taffy::Style = mirrored.clone().into();
        assert_eq!(back, taffy::Style::DEFAULT);
        assert_eq!(mirrored, Style::from(taffy::Style::DEFAULT));
    }

    #[test]
    fn populated_style_round_trips() {
        let style = Style {
            display: Display::Grid,
            position: Position::Sticky,
            size: DimensionSize { width: TaffyDimension::FitContentPercent(0.5), height: TaffyDimension::Stretch },
            margin: LengthPercentageAutoRect {
                left: LengthPercentageAuto::Auto,
                right: LengthPercentageAuto::Length(3.0),
                top: LengthPercentageAuto::Percent(0.1),
                bottom: LengthPercentageAuto::Length(0.0),
            },
            align_self: Some(AlignItems { keyword: AlignItemsKeyword::Baseline, safety: AlignmentSafety::Unsafe }),
            contain: Contain { layout: true, paint: true },
            grid_template_columns: vec![
                GridTemplateComponent::Single(TrackSizingFunction {
                    min: MinTrackSizingFunction::MinContent,
                    max: MaxTrackSizingFunction::Fr(2.0),
                }),
                GridTemplateComponent::Repeat(GridTemplateRepetition {
                    count: RepetitionCount::Count(2),
                    tracks: vec![TrackSizingFunction {
                        min: MinTrackSizingFunction::Length(4.0),
                        max: MaxTrackSizingFunction::FitContentPx(9.0),
                    }],
                    line_names: vec![vec!["a".into()], vec![]],
                }),
            ],
            grid_template_areas: Some(GridTemplateAreas {
                areas: vec![GridTemplateArea {
                    name: "main".into(),
                    row_start: 1,
                    row_end: 3,
                    column_start: 2,
                    column_end: 4,
                }],
                row_count: 2,
                column_count: 3,
            }),
            grid_row: GridPlacementLine { start: GridPlacement::NamedSpan { name: "n".into(), count: 2 }, end: GridPlacement::Line(-1) },
            ..Style::default()
        };

        let taffy_style: taffy::Style = style.clone().into();
        assert_eq!(Style::from(taffy_style), style);
    }

    #[test]
    fn unsupported_calc_values_degrade_to_auto() {
        // `calc()` can only be built through the raw API; make sure reading one never panics.
        // Taffy only needs a non-null, 8-byte aligned tag here; the pointer is never dereferenced.
        let handle = std::ptr::NonNull::<u64>::dangling().as_ptr() as *const ();
        let calc = taffy::Dimension::calc(handle);
        assert_eq!(TaffyDimension::from(calc), TaffyDimension::Auto);
    }
}
