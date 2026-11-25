//! CSS Grid properties of [`Style`](crate::style::Style).

use boltffi::*;
use taffy::geometry as g;
use taffy::style as t;

use crate::style::mirror_enum;

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GridAutoFlow {
    Row,
    Column,
    RowDense,
    ColumnDense,
}
mirror_enum!(GridAutoFlow <=> t::GridAutoFlow { Row, Column, RowDense, ColumnDense });

/// The minimum of a track size (`minmax(min, max)` first argument).
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum MinTrackSizingFunction {
    Length(f32),
    Percent(f32),
    Auto,
    MinContent,
    MaxContent,
}

impl From<t::MinTrackSizingFunction> for MinTrackSizingFunction {
    fn from(v: t::MinTrackSizingFunction) -> Self {
        use t::ExpandedMinTrackSizingFunction as E;
        match v.expand() {
            E::Length(x) => MinTrackSizingFunction::Length(x),
            E::Percent(x) => MinTrackSizingFunction::Percent(x),
            E::Auto => MinTrackSizingFunction::Auto,
            E::MinContent => MinTrackSizingFunction::MinContent,
            E::MaxContent => MinTrackSizingFunction::MaxContent,
            // `calc()` is never constructed by this crate.
            _ => MinTrackSizingFunction::Auto,
        }
    }
}

impl From<MinTrackSizingFunction> for t::MinTrackSizingFunction {
    fn from(v: MinTrackSizingFunction) -> Self {
        match v {
            MinTrackSizingFunction::Length(x) => t::MinTrackSizingFunction::length(x),
            MinTrackSizingFunction::Percent(x) => t::MinTrackSizingFunction::percent(x),
            MinTrackSizingFunction::Auto => t::MinTrackSizingFunction::auto(),
            MinTrackSizingFunction::MinContent => t::MinTrackSizingFunction::min_content(),
            MinTrackSizingFunction::MaxContent => t::MinTrackSizingFunction::max_content(),
        }
    }
}

/// The maximum of a track size (`minmax(min, max)` second argument); also allows flexible `fr` tracks.
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum MaxTrackSizingFunction {
    Length(f32),
    Percent(f32),
    Auto,
    MinContent,
    MaxContent,
    FitContentPx(f32),
    FitContentPercent(f32),
    Fr(f32),
}

impl From<t::MaxTrackSizingFunction> for MaxTrackSizingFunction {
    fn from(v: t::MaxTrackSizingFunction) -> Self {
        use t::ExpandedMaxTrackSizingFunction as E;
        match v.expand() {
            E::Length(x) => MaxTrackSizingFunction::Length(x),
            E::Percent(x) => MaxTrackSizingFunction::Percent(x),
            E::Auto => MaxTrackSizingFunction::Auto,
            E::MinContent => MaxTrackSizingFunction::MinContent,
            E::MaxContent => MaxTrackSizingFunction::MaxContent,
            E::FitContentPx(x) => MaxTrackSizingFunction::FitContentPx(x),
            E::FitContentPercent(x) => MaxTrackSizingFunction::FitContentPercent(x),
            E::Fr(x) => MaxTrackSizingFunction::Fr(x),
            // `calc()` is never constructed by this crate.
            _ => MaxTrackSizingFunction::Auto,
        }
    }
}

impl From<MaxTrackSizingFunction> for t::MaxTrackSizingFunction {
    fn from(v: MaxTrackSizingFunction) -> Self {
        match v {
            MaxTrackSizingFunction::Length(x) => t::MaxTrackSizingFunction::length(x),
            MaxTrackSizingFunction::Percent(x) => t::MaxTrackSizingFunction::percent(x),
            MaxTrackSizingFunction::Auto => t::MaxTrackSizingFunction::auto(),
            MaxTrackSizingFunction::MinContent => t::MaxTrackSizingFunction::min_content(),
            MaxTrackSizingFunction::MaxContent => t::MaxTrackSizingFunction::max_content(),
            MaxTrackSizingFunction::FitContentPx(x) => t::MaxTrackSizingFunction::fit_content_px(x),
            MaxTrackSizingFunction::FitContentPercent(x) => t::MaxTrackSizingFunction::fit_content_percent(x),
            MaxTrackSizingFunction::Fr(x) => t::MaxTrackSizingFunction::fr(x),
        }
    }
}

/// A grid track size: `minmax(min, max)`. A single value `v` is expressed as `min == max == v`
/// (or `min: auto, max: fr(n)` for `1fr`).
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrackSizingFunction {
    pub min: MinTrackSizingFunction,
    pub max: MaxTrackSizingFunction,
}

impl From<t::TrackSizingFunction> for TrackSizingFunction {
    fn from(v: t::TrackSizingFunction) -> Self {
        TrackSizingFunction { min: v.min.into(), max: v.max.into() }
    }
}

impl From<TrackSizingFunction> for t::TrackSizingFunction {
    fn from(v: TrackSizingFunction) -> Self {
        g::MinMax { min: v.min.into(), max: v.max.into() }
    }
}

#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RepetitionCount {
    AutoFill,
    AutoFit,
    Count(u16),
}

impl From<t::RepetitionCount> for RepetitionCount {
    fn from(v: t::RepetitionCount) -> Self {
        match v {
            t::RepetitionCount::AutoFill => RepetitionCount::AutoFill,
            t::RepetitionCount::AutoFit => RepetitionCount::AutoFit,
            t::RepetitionCount::Count(n) => RepetitionCount::Count(n),
        }
    }
}

impl From<RepetitionCount> for t::RepetitionCount {
    fn from(v: RepetitionCount) -> Self {
        match v {
            RepetitionCount::AutoFill => t::RepetitionCount::AutoFill,
            RepetitionCount::AutoFit => t::RepetitionCount::AutoFit,
            RepetitionCount::Count(n) => t::RepetitionCount::Count(n),
        }
    }
}

/// `repeat(count, tracks...)` inside `grid-template-rows` / `grid-template-columns`.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct GridTemplateRepetition {
    pub count: RepetitionCount,
    pub tracks: Vec<TrackSizingFunction>,
    /// Line names, one list per line: `tracks.len() + 1` entries.
    pub line_names: Vec<Vec<String>>,
}

impl From<t::GridTemplateRepetition<String>> for GridTemplateRepetition {
    fn from(v: t::GridTemplateRepetition<String>) -> Self {
        GridTemplateRepetition {
            count: v.count.into(),
            tracks: v.tracks.into_iter().map(Into::into).collect(),
            line_names: v.line_names,
        }
    }
}

impl From<GridTemplateRepetition> for t::GridTemplateRepetition<String> {
    fn from(v: GridTemplateRepetition) -> Self {
        t::GridTemplateRepetition {
            count: v.count.into(),
            tracks: v.tracks.into_iter().map(Into::into).collect(),
            line_names: v.line_names,
        }
    }
}

/// One entry of `grid-template-rows` / `grid-template-columns`.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub enum GridTemplateComponent {
    Single(TrackSizingFunction),
    Repeat(GridTemplateRepetition),
}

impl From<t::GridTemplateComponent<String>> for GridTemplateComponent {
    fn from(v: t::GridTemplateComponent<String>) -> Self {
        match v {
            t::GridTemplateComponent::Single(track) => GridTemplateComponent::Single(track.into()),
            t::GridTemplateComponent::Repeat(rep) => GridTemplateComponent::Repeat(rep.into()),
        }
    }
}

impl From<GridTemplateComponent> for t::GridTemplateComponent<String> {
    fn from(v: GridTemplateComponent) -> Self {
        match v {
            GridTemplateComponent::Single(track) => t::GridTemplateComponent::Single(track.into()),
            GridTemplateComponent::Repeat(rep) => t::GridTemplateComponent::Repeat(rep.into()),
        }
    }
}

/// Where a grid item starts or ends along one axis.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub enum GridPlacement {
    Auto,
    /// A 1-based line index; negative values count from the end.
    Line(i16),
    /// The `index`-th line called `name`.
    NamedLine { name: String, index: i16 },
    Span(u16),
    /// A span of `count` lines counted by lines called `name`.
    NamedSpan { name: String, count: u16 },
}

impl From<t::GridPlacement<String>> for GridPlacement {
    fn from(v: t::GridPlacement<String>) -> Self {
        match v {
            t::GridPlacement::Auto => GridPlacement::Auto,
            t::GridPlacement::Line(line) => GridPlacement::Line(line.as_i16()),
            t::GridPlacement::NamedLine(name, index) => GridPlacement::NamedLine { name, index },
            t::GridPlacement::Span(n) => GridPlacement::Span(n),
            t::GridPlacement::NamedSpan(name, count) => GridPlacement::NamedSpan { name, count },
        }
    }
}

impl From<GridPlacement> for t::GridPlacement<String> {
    fn from(v: GridPlacement) -> Self {
        match v {
            GridPlacement::Auto => t::GridPlacement::Auto,
            GridPlacement::Line(line) => t::GridPlacement::Line(line.into()),
            GridPlacement::NamedLine { name, index } => t::GridPlacement::NamedLine(name, index),
            GridPlacement::Span(n) => t::GridPlacement::Span(n),
            GridPlacement::NamedSpan { name, count } => t::GridPlacement::NamedSpan(name, count),
        }
    }
}

/// `grid-row` / `grid-column`: start and end placement.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct GridPlacementLine {
    pub start: GridPlacement,
    pub end: GridPlacement,
}

impl From<g::Line<t::GridPlacement<String>>> for GridPlacementLine {
    fn from(v: g::Line<t::GridPlacement<String>>) -> Self {
        GridPlacementLine { start: v.start.into(), end: v.end.into() }
    }
}

impl From<GridPlacementLine> for g::Line<t::GridPlacement<String>> {
    fn from(v: GridPlacementLine) -> Self {
        g::Line { start: v.start.into(), end: v.end.into() }
    }
}

/// A named rectangle of `grid-template-areas`. Line numbers are 1-based.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct GridTemplateArea {
    pub name: String,
    pub row_start: u16,
    pub row_end: u16,
    pub column_start: u16,
    pub column_end: u16,
}

impl From<t::GridTemplateArea<String>> for GridTemplateArea {
    fn from(v: t::GridTemplateArea<String>) -> Self {
        GridTemplateArea {
            name: v.name,
            row_start: v.row_start,
            row_end: v.row_end,
            column_start: v.column_start,
            column_end: v.column_end,
        }
    }
}

impl From<GridTemplateArea> for t::GridTemplateArea<String> {
    fn from(v: GridTemplateArea) -> Self {
        t::GridTemplateArea {
            name: v.name,
            row_start: v.row_start,
            row_end: v.row_end,
            column_start: v.column_start,
            column_end: v.column_end,
        }
    }
}

#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct GridTemplateAreas {
    pub areas: Vec<GridTemplateArea>,
    pub row_count: u16,
    pub column_count: u16,
}

impl From<t::GridTemplateAreas<String>> for GridTemplateAreas {
    fn from(v: t::GridTemplateAreas<String>) -> Self {
        GridTemplateAreas {
            areas: v.areas.into_iter().map(Into::into).collect(),
            row_count: v.row_count,
            column_count: v.column_count,
        }
    }
}

impl From<GridTemplateAreas> for t::GridTemplateAreas<String> {
    fn from(v: GridTemplateAreas) -> Self {
        t::GridTemplateAreas {
            areas: v.areas.into_iter().map(Into::into).collect(),
            row_count: v.row_count,
            column_count: v.column_count,
        }
    }
}

// ---------------------------------------------------------------------------------------
// Computed grid information
// ---------------------------------------------------------------------------------------

/// The start and end of one grid track along its axis, relative to the container's border box.
#[data]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TrackPosition {
    pub start: f32,
    pub end: f32,
}

/// A half-open range of track indices.
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TrackRange {
    pub start: u32,
    pub end: u32,
}

/// The tracks of one axis of a laid-out grid.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct GridAxisInfo {
    /// Number of implicit tracks before the explicit ones.
    pub negative_implicit_tracks: u16,
    pub explicit_tracks: u16,
    /// Number of implicit tracks after the explicit ones.
    pub positive_implicit_tracks: u16,
    /// Where each track ended up, including the container's border and padding, `gap`, content alignment and
    /// collapsed tracks.
    pub positions: Vec<TrackPosition>,
    /// Runs of `auto-fit` tracks that collapsed to nothing (indices into `positions`).
    pub collapsed_tracks: Vec<TrackRange>,
    /// The position of the axis' only grid line when it has no tracks.
    pub empty_axis_line: Option<f32>,
    /// The names of every grid line of the full grid (implicit tracks included), in line order. Empty if no line
    /// has a name.
    pub line_names: Vec<Vec<String>>,
}

impl From<&taffy::DetailedGridTracksInfo> for GridAxisInfo {
    fn from(v: &taffy::DetailedGridTracksInfo) -> Self {
        GridAxisInfo {
            negative_implicit_tracks: v.negative_implicit_tracks,
            explicit_tracks: v.explicit_tracks,
            positive_implicit_tracks: v.positive_implicit_tracks,
            positions: v.positions.iter().map(|p| TrackPosition { start: p.start, end: p.end }).collect(),
            collapsed_tracks: v
                .collapsed_tracks
                .iter()
                .map(|r| TrackRange { start: r.start as u32, end: r.end as u32 })
                .collect(),
            empty_axis_line: v.empty_axis_line,
            line_names: v.iter_line_names().map(|names| names.to_vec()).collect(),
        }
    }
}

/// The cells a grid item occupies, as 1-based grid line numbers.
#[data]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GridItemPlacement {
    pub row_start: u16,
    pub row_end: u16,
    pub column_start: u16,
    pub column_end: u16,
}

/// What a grid container resolved to: its tracks and where each in-flow child was placed.
#[data]
#[derive(Clone, Debug, PartialEq)]
pub struct GridLayoutInfo {
    pub rows: GridAxisInfo,
    pub columns: GridAxisInfo,
    /// One entry per in-flow child, in child order.
    pub items: Vec<GridItemPlacement>,
}

impl From<&taffy::DetailedGridInfo> for GridLayoutInfo {
    fn from(v: &taffy::DetailedGridInfo) -> Self {
        GridLayoutInfo {
            rows: (&v.rows).into(),
            columns: (&v.columns).into(),
            items: v
                .items
                .iter()
                .map(|i| GridItemPlacement {
                    row_start: i.row_start,
                    row_end: i.row_end,
                    column_start: i.column_start,
                    column_end: i.column_end,
                })
                .collect(),
        }
    }
}
