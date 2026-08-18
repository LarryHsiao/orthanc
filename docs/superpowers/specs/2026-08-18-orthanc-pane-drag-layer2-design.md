# Orthanc — Pane Move & Re-split Design (Layer 2)

## Goal

Extend the drag started in layer 1 so a drop on the **edge** of a target
pane lifts the dragged pane out of the tree and re-splices it in beside
the target, on the side the pointer released over — rather than the
swap a drop on the target's centre already performs. Layer 1 shipped
(`Workspace.swap`, the draggable title label, the amber drop highlight);
this spec covers only what layer 1 deliberately deferred.

## Why this, and why now

Swap answers *"put that session where this one is"* — a same-shape
relabeling that can never misfire. It does not answer *"put that
session **next to** this one"* when no slot already sits there, or
*"move this session out of its column and into that row."* Those need
the tree's actual shape to change, which is exactly what layer 1's own
design named as the harder, deferred half:

- **Removal can dissolve the very split a drop meant to land in.** Drag
  a pane onto its only sibling and `_without`'s single-child collapse
  fires before any insert runs — the split you were about to insert
  into is gone by the time you'd try.
- **Every insertion path is keyed off `focusedId`, not an arbitrary
  anchor.** `_insertBeside`/`_wrapFocusedChild` (`lib/workspace.dart`)
  answer "where does the focused pane's next sibling go," never "where
  does an arbitrary target pane's next sibling go."

Both turn out to have a clean resolution, worked through below, that
needed no change to any already-shipped code beyond one small, provably
behavior-preserving extraction (see **Architecture — collapse
cleanup**).

## Decisions

1. **Five drop zones per target pane: four edges, one centre.** The
   pointer's position inside the hovered pane's own rect is compared
   against all four edges; whichever is nearest wins, unless every edge
   sits farther than `dropEdgeBand` (`0.25` — the outer quarter of the
   pane on each side), in which case the pointer is in the centre
   dead-zone and layer 1's swap applies unchanged. This is a pure
   function of the target's `PaneRect` and the pointer's fractional
   position — no widget needed to test it. See the wireframe
   (`wireframe-orthanc-pane-drag-layer2.html`, Frame A) for the
   geometry, and Frame E for the two live highlight shapes.
2. **Removal always runs before the target is re-located.** The
   dragged pane is removed first (`_without`, unchanged); the insert
   step then searches the tree **that remains** for wherever the target
   id now lives — never a reference captured before removal. This is
   the whole resolution to the dissolve hazard: a split that
   disappeared during removal was never a valid landing spot to begin
   with, and the fresh lookup can never point at it. Frame D of the
   wireframe walks the tightest case — dropping a pane back onto its
   own only sibling — end to end.
3. **Insertion gets its own anchor-generalized methods, not a
   retrofit of `split()`'s.** `_insertBeside`/`_wrapFocusedChild`
   always insert *after* an implicit `focusedId` anchor; move needs
   *before or after* an explicit, arbitrary anchor (`left`/`up` mean
   before, `right`/`down` mean after). The shapes are close enough that
   folding them into one generalized implementation is tempting, but
   that would mean editing `split()`'s already-shipped, already-tested
   path for a feature that doesn't need it changed — out of scope here.
   Named plainly under **Deferred** as a follow-up worth doing on its
   own, not silently done alongside this.
4. **Collapse cleanup is lifted into one shared helper — its third
   caller has arrived.** `close()` and `swap()` already run an
   identical "recompute collapsibility on the new tree, intersect,
   release any column left holding nothing but bars" sequence; `move`
   needs the exact same sequence a third time. Per this codebase's own
   duplication rule, three call sites is the line — `_reconciledCollapse`
   is extracted and all three route through it. `close()`'s existing
   `.where((id) => id != closedId)` drops out in the same pass: the
   entry can never survive the intersection anyway once the closed
   pane's id is gone from the tree `_collectCollapsible` walks — a
   provably behavior-preserving simplification, not a functional
   change.
5. **A same-axis edge drop is a plain sibling insert; a
   cross-axis edge drop wraps the target in a new split.** Exactly
   `split()`'s own two rules (`workspace.dart:162–167`), generalized to
   an explicit anchor instead of `focusedId`. Dropping on `b`'s right
   edge inside `row[a, b, c]` reorders in place
   (`row[b, a, c]`, no new split); dropping on `b`'s top edge when
   `b`'s parent is a column wraps `b` alone in a fresh row
   (Frame B of the wireframe).
6. **The moved pane takes focus; ratios re-even at the insertion
   point.** Same convention as `swap`/`toggleCollapse`/`split`.
   Ratios: every sibling in the split the pane lands in re-evens via
   `evenRatios`, matching `_insertSibling`'s and `_wrapInSplit`'s
   existing behavior exactly — including the case where the pane lands
   back in the same 2-slot split it started in, which visibly resets a
   previously-dragged ratio. Named plainly rather than hidden: dropping
   a pane back where it already was is well-defined, just not free.
7. **No new gesture.** The same pan already wired for swap (grip →
   title label, see the layer-1 spec) supplies every frame's pointer
   position; only the *interpretation* of where it lands changes,
   decided entirely in `WorkspaceView`, never in `PaneBar`/`PaneView`.

## Architecture

**`PaneRect.zoneAt(double x, double y)`** (`lib/layout_node.dart`, new)
— `x`/`y` are absolute fractions of the whole window, the same space
`paneRects()` already returns. Converts to local fractions within this
rect, measures the distance to all four edges, returns whichever edge
is nearest, or `null` when the nearest is still farther than
`dropEdgeBand` (a new named constant beside `minPaneRatio`). A corner
exactly equidistant from two edges picks a fixed, deterministic
tie-break (`left` before `right` before `up` before `down`) — an
accepted arbitrary choice for an input real dragging essentially never
produces exactly.

**`Workspace.move({required String sourceId, required String targetId, required Direction side})`**
(`lib/workspace.dart`). No-ops when `sourceId == targetId` or either id
is absent from `sessionIds`. `side` picks the axis (`left`/`right` →
row, `up`/`down` → column) and which end (`left`/`up` → before,
`right`/`down` → after). Removes `sourceId` via the existing `_without`,
then calls new static helpers `_insertAdjacent`/`_wrapAdjacent` —
structurally mirroring `_insertBeside`/`_insertSibling`/
`_wrapFocusedChild`/`_wrapInSplit`, but keyed to an explicit anchor id
and an explicit before/after, so they need no instance state (`this` /
`focusedId`) at all. Focuses `sourceId`; collapse state runs through
`_reconciledCollapse`.

**`_reconciledCollapse(LayoutNode newRoot, Set<String> prior)`**
(`lib/workspace.dart`, new private helper, extracted from the logic
`close()` already has and `swap()` already duplicates). `close()` and
`swap()` are both migrated to call it; no other change to either.

**`WorkspaceView`** (`lib/workspace_view.dart`) gains `Direction?
_dragHoverSide` alongside the existing `_dragSourceId`/`_dragHoverId`.
`_onDragUpdate` computes it once a hover pane is found:
`workspace.paneRects()[hoverId]!.zoneAt(fx, fy)`. `_onDragEnd` branches
on it: `null` → `workspace.swap(source, target)` (today's behavior,
unchanged); non-null → `workspace.move(sourceId: source, targetId:
target, side: dragHoverSide)`.

**`PaneView`** gains `Direction? dropSide` alongside the existing
`isDropTarget` (which keeps its exact current meaning — "is this pane
the current hover target at all"). `dropSide` is only read when
`isDropTarget` is true: `null` draws today's full-pane amber overlay
(swap); non-null draws a new edge-band overlay in a second accent
colour, sized to the same `dropEdgeBand` fraction the hit-test itself
uses, on the named side only. Both stay overlays — neither ever changes
a pane's layout size, the same discipline `focusBorderKey`/
`attentionBorderKey`/`dropHighlightKey` already established.

## Testing

| Unit | Tested by |
|---|---|
| `PaneRect.zoneAt` — all four edges, the centre dead-zone, boundary values at exactly `dropEdgeBand`, corner tie-break | unit tests, no engine |
| `Workspace.move` — same-axis sibling insert (before and after), cross-axis wrap, reaches across branches, the dissolve-then-reinsert case (both sides), reordering within a flat 3+ split, no-op on equal or missing ids, focuses the moved pane, ratios re-even at the landing split | unit tests, no engine |
| `_reconciledCollapse` extraction — every existing `close()` and `swap()` collapse test still passes unchanged, plus new `move()` collapse tests: a stale entry the move makes illegal is dropped, an unrelated entry survives | unit tests, no engine |
| `PaneView` — the edge-band overlay renders on the named side only, sized to `dropEdgeBand`, distinct from the full-pane swap overlay | widget tests |
| The five zones read correctly under a real pointer, the highlight shape matches the zone, a drop lands where the highlight promised, both platforms | by eye, running the app |

## Definition of done

Dragging a pane's label and releasing over another pane's edge lifts
the dragged pane out and re-splices it in on that side — reordering in
place when the target's parent already runs that axis, wrapping the
target in a new split otherwise — while a release over the same pane's
centre still swaps, exactly as layer 1 shipped. The moved pane is
focused wherever it lands. A stale collapse entry never survives a move
that makes it illegal, and a move never invents a new one. The edge-
band highlight and the full-pane swap highlight are visibly distinct
while dragging. Confirmed by hand on both macOS and Windows.

## Deferred — not in this change

- Unifying `_insertAdjacent`/`_wrapAdjacent` with `split()`'s existing
  `_insertBeside`/`_wrapFocusedChild`/`_insertSibling`/`_wrapInSplit` —
  named in Decision 3 as a real, surfaced simplification opportunity,
  left for its own pass rather than bundled here.
- Any drag affordance for reaching a *corner* explicitly (a sixth
  "quadrant" zone) — the four-edge-plus-centre scheme is the whole
  design.
- A floating drag ghost or live layout preview — still deferred from
  layer 1, unchanged by this pass.
- Persisting or animating the transition between zones as the pointer
  crosses a boundary — the highlight simply swaps state on the next
  frame, no transition designed.

## Watch out

- `move`'s no-op guard (`sessionIds.contains(...)`) walks the tree
  twice (once per id) on every call — cheap at the pane counts this
  app runs, but worth knowing if a future workspace ever holds enough
  panes for that to matter.
- The corner tie-break in `zoneAt` is arbitrary by design — do not let
  a future edit make it seem load-bearing; if it ever needs to change,
  no real usage should be able to tell the difference.
- `_reconciledCollapse`'s extraction must be verified against the
  *existing* `close()` test suite before `move()` is built on top of
  it — a regression there would be silently inherited by every caller,
  not just the new one.
