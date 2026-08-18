# Orthanc — Pane Drag (Swap) Design

## Goal

Let a pane be picked up by its bar and dropped onto another pane to trade
places with it — a mouse-driven rearrangement to sit beside the keyboard's
`Alt+Arrow` focus move and the divider drag that already resizes a split.
This is **layer 1 of two** for pane drag-and-drop: a swap only ever
exchanges which session fills two existing slots. It never changes the
tree's shape, axes, or ratios, and it can never produce a tree `close()`
or `split()` couldn't already produce on their own.

## Why this, and why now

`Workspace` already carries the raw material for this — `paneRects()`
gives fractional geometry for every pane, exactly what a drop needs to
know "which pane is under the cursor." What is missing is any way to move
a pane without closing and re-opening a session: today, putting the
right-hand session on the left means closing both and reopening them in
the order you wanted, losing pty state either way you'd never accept.

A full move-and-re-split — lifting a pane out of the tree and re-inserting
it beside another, deepening or flattening the tree in the process — was
sketched during wireframing (`/henneth` at the time,
`wireframe-orthanc-pane-drag.html`) and set aside on purpose. Removal can
dissolve the very split a drop meant to land in (drop a pane on its only
sibling and `_without`'s single-child collapse fires before the insert
ever runs), and every insertion path today (`_insertBeside`,
`_wrapFocusedChild`) is keyed off `focusedId`, not an arbitrary anchor —
generalizing them is real, separate work. Swap carries none of that risk:
it is a same-shape relabeling, provably total over any two ids in the
tree, and answers the ordinary want — *"put that session where this one
is"* — without touching anything else. Move-and-re-split is deferred to
a later pass; see **Deferred** below.

## Decisions

1. **A swap trades session ids between two slots; nothing about the
   tree's shape moves.** `Workspace.swap(sourceId, targetId)` walks the
   tree and relabels the two `PaneNode` leaves holding `sourceId` and
   `targetId`; every `SplitNode`'s axis, children count, and — critically
   — **ratios** are untouched. A slot's size belongs to the slot, not to
   whichever session currently fills it: drag a wide pane onto a narrow
   one and the wide pane takes the narrow slot's width, not the other way
   around. This was weighed against carrying the ratio along with the
   session — rejected, because that reading makes "swap" behave like a
   partial move, blurring the line this design draws between the two
   layers.

2. **The drag starts from the pane's title label, not the bar as a
   whole, and never from a dedicated icon.** The bar already answers to
   three gestures — tap collapses, double-tap expands, right-click
   renames (`pane_view.dart`, `pane_bar.dart`). Revised after the first
   pass: a dedicated grip glyph was tried and dropped — the label alone
   is the handle, so the bar carries no new icon. The label sits in its
   own `Expanded` region distinct from the fixed-width collapse icon, so
   pan still gets a hit region of its own rather than contesting the
   existing ones; a `MouseRegion` grab cursor is the only added
   affordance, not a glyph. The terminal body is never a drag source —
   see Watch Out — matching the existing rule that only the bar reacts
   to a click at all. Disabled while the label is mid-rename (the inline
   `TextField` replaces it), so a drag never fights text selection in
   the field.

3. **A pane may be dragged whenever the workspace holds more than one
   pane — collapsed or not, single-row column or deep in a nested
   split.** Swap has no column-only restriction the way collapse does;
   any two panes anywhere in the tree may trade places. `Workspace`
   already exposes this as `isSplit` (true whenever `root is
   SplitNode`); the same flag `WorkspaceView` already threads down as
   `highlightFocus` is threaded a second time, under its own name, to
   gate the grip — reusing `highlightFocus` itself for a second purpose
   would blur what that flag means.

4. **A collapse entry that no longer applies after a swap is dropped,
   never carried along, and never invented.** `collapsedIds` holds
   session ids, not tree positions, so relabeling a slot's content can
   leave a `collapsedIds` entry pointing at a pane whose new parent isn't
   a column — the same shape of drift `close()` already guards against
   for a pane hoisted out of a dissolved split. `swap` runs the identical
   invariant-restoring step `close()` already uses: intersect
   `collapsedIds` against `collapsibleIds` recomputed on the swapped
   tree (via the existing `_collectCollapsible`), then release any column
   the swap would otherwise leave holding nothing but bars (via the
   existing `_releaseEmptiedColumns`). Neither swapped id is ever *added*
   to `collapsedIds` by the swap itself — only entries already present
   can be dropped, never manufactured. This is what "un-collapse on
   landing" means in practice: not a special case for a collapsed source
   or target, but the same cleanup `close()` already performs, run again
   here.
5. **Dropping a pane onto itself, or a drag that never crosses another
   pane's rect, is a no-op.** `swap(id, id)` returns the same
   `Workspace` unchanged. A drag released over empty space between panes
   (the divider gutter) or outside the whole tree resolves to no target
   at all, and the gesture ends with nothing moved.
6. **The swapped-in pane takes focus.** `swap(sourceId, targetId)` sets
   `focusedId` to `sourceId` — the pane that was picked up — mirroring
   `toggleCollapse`'s and `split`'s existing convention of focusing the
   pane the operation acted on, wherever it ends up.

## Architecture

**`Workspace.swap(String sourceId, String targetId)`**
(`lib/workspace.dart`, to sit just after `_releaseEmptiedColumns`, ahead
of `paneRects()` — it depends on `_collectCollapsible` and
`_releaseEmptiedColumns`, both defined just above it). No-ops on
`sourceId == targetId`. A private `_swapped(node, a, b)` walks the tree
exactly like `_resized`'s walk shape: return a relabeled `PaneNode` for a
leaf matching either id, otherwise return the node unchanged; recurse
into a `SplitNode`'s children, rebuilding it with the same `axis` and
`ratios`, only the `children` list's *content* (not its length or order)
changes. After the walk, `collapsedIds` is passed through the same
collect-and-release pass `close()` already performs.

**`PaneBar`** (`lib/pane_bar.dart`) gains a `canDrag` flag and a small
grip — a `Text` glyph in the same style as the existing `⤢`/`⤡`
affordance, planted at the *start* of the bar's `Row` (opposite the
collapse icon at the end), shown only when `canDrag`. The grip carries
its own `GestureDetector` for `onPanStart`/`onPanUpdate`/`onPanEnd`,
nested inside the bar exactly the way the bar's existing
`onSecondaryTapUp` detector already coexists with `PaneView`'s outer
tap/double-tap detector — a new, small hit region, not a change to any
existing one. `PaneBar` reports only its own session id and the pointer's
*global* position; it carries no drag-target logic of its own.

**`PaneView`** threads the three callbacks and `canDrag` through to
`PaneBar`, unchanged in every other respect — the same pass-through shape
`canCollapse`/`onToggleCollapse` already have.

**`SplitView`** threads `canDrag` and the three callbacks down through
`_shrinkablePane`/`_childSplitView`, exactly as `onToggleCollapse` and
`onExpand` already are.

**`WorkspaceView`** owns the drag state: `String? _dragSourceId` (the
pane being dragged, null when idle) and `String? _dragHoverId` (the pane
currently under the pointer, null when over no pane or over the source
itself). A `GlobalKey` wraps the tree's own bounding box (a bare
`Container` around the existing `SplitView`, needed only so a pointer's
*global* position can be converted to the same 0..1 fractional space
`paneRects()` already speaks) — `onPanUpdate` converts the pointer's
global position through that box into a fraction, then finds whichever
entry of `workspace.paneRects()` contains it. `onPanEnd` calls
`workspace.swap(source, hover)` when a hover target is set, exactly the
way the existing divider drag calls `workspace.resizeSplit(...)` on every
`onHorizontalDragUpdate` — the same per-frame `setState` cost profile
this codebase already accepts for a live drag.

**Drop feedback, this pass:** a highlight only — no floating ghost, no
live layout preview. The hovered target pane gains a third overlay
border in `PaneView`'s existing `Stack` (beside the established focus and
attention overlays — see `PaneView.focusBorderKey`'s doc comment for why
an overlay, never a decoration, is required here), and the pane actively
being dragged dims slightly via a bare `Opacity` wrap. Both reuse the
"paint over, never resize" discipline already established for focus and
attention. A floating drag proxy and a live re-flow preview were sketched
in the wireframe and are explicitly deferred — see below.

## Testing

| Unit | Tested by |
|---|---|
| `Workspace.swap` — trades session ids, ratios stay with the slot, reaches across nested branches, no-ops on identical ids, focuses the swapped-in pane, drops a collapse entry the swap makes illegal, leaves an unrelated collapse entry alone | unit tests, no engine |
| `PaneBar` — the grip fires `onDragStart`/`onDragUpdate`/`onDragEnd` with the pane's own session id; right-click rename still fires alongside it | widget tests |
| `PaneView` — a drag on the grip does **not** also fire `onToggleCollapse`/`onExpand` (the gesture-arena proof); an ordinary tap/double-tap on the rest of the bar still does | widget tests |
| Drop highlight appearing over the hovered pane, dragged pane dimming, a swap landing on drop, a drag released over the gutter or off the tree doing nothing | by eye, running the app, both platforms |

## Definition of done

Pressing a pane's grip and dragging it onto another pane swaps the two
sessions in place — sizes stay with their slots, not with the sessions —
and focuses the dragged session wherever it lands; releasing over the
gutter, off the tree, or back onto the same pane changes nothing;
dragging a pane that was collapsed, or dropping onto one, never leaves a
stale collapse flag on a pane whose new position can't legally hold one;
an ordinary tap, double-tap, and right-click on the bar all still work
exactly as before, confirmed by hand on both macOS and Windows.

## Deferred — not in this change

- **Move-and-re-split** (layer 2): dropping on an edge region of a
  target pane to lift the dragged pane out and re-insert it as a new
  split there, rather than swapping. Needs `_insertBeside` and
  `_wrapFocusedChild` generalized to an explicit anchor id rather than
  `focusedId`, and needs the removal-can-dissolve-the-target-split
  hazard named in "Why this, and why now" solved first.
- A floating drag ghost that follows the cursor, and any live preview of
  the resulting layout before release — sketched in the wireframe,
  dropped for cost; the drop-zone highlight alone carries the feedback
  this pass needs.
- Dragging via a modifier-click on the terminal body, as an alternative
  to the grip.
- Any keyboard-only way to trigger a swap.

## Watch out

- The grip must stay off the terminal body entirely — `pane_view.dart`'s
  existing `Listener`-not-`GestureDetector` choice for focus exists
  because "a `GestureDetector` here would compete with xterm's own tap
  recognizer and routinely lose it on a brisk click." A pan recognizer
  anywhere over the body inherits that same risk.
- The gesture-arena coexistence between the grip's pan and `PaneView`'s
  outer tap/double-tap is the one place this design could quietly break
  an existing gesture — prove it with a widget test, not by eye alone.
- `swap`'s collapse cleanup must only ever *drop* entries, never add
  one — a swap must not be able to collapse a pane that was never
  collapsed to begin with.
- The bounding-box `GlobalKey` added to `WorkspaceView` must wrap the
  same region `paneRects()` describes (the whole tree, corner to corner)
  — a mismatch between the box measured and the fractions computed would
  make every hit-test land on the wrong pane.
