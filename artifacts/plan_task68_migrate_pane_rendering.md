# Plan: Task 68 — Migrate Terminal.hs pane rendering to tank-layout

## Goal

Replace the imperative `renderPaneLayout` in Terminal.hs with a two-phase approach:
1. Build a tank-layout `Layout` tree from the `PaneLayout` tree
2. Call `renderLayout` to produce a `CellGrid`
3. Emit the grid to stdout using tank-layout's ANSI backend
4. Overdraw pane borders on top (preserving active-pane color highlighting)

Keep `renderSinglePane` and `findPaneRegion` unchanged.

## Key insight: VTerm-to-CellGrid gap

`gridToCellGrid` in CellAdapter converts from CRDT Grid (absolute-line-addressed, epoch-tagged),
NOT from VTerm (V.Vector (V.Vector Cell), row/col indexing, Emulator.Color which is Color256 Word8).

Need a new `vtermToCellGrid :: VTerm -> LC.CellGrid` function in CellAdapter that:
- Uses `vtGetCell`/`vtGetSize` (the public API)
- Converts Emulator.Color (DefaultColor | Color256 Word8) to LC.Color (Default | RGB)
- Converts Emulator.Attrs flags to LC.Cell booleans

## Steps

1. Add `vtermToCellGrid` and `convertEmulatorCell` to CellAdapter.hs
   - verify: builds
2. Add `buildLayout`, `emitGrid`, `drawPaneBorders` to Terminal.hs
   - verify: builds
3. Replace `renderAllPanes` to use new pipeline
   - verify: builds, tests pass
4. Remove now-dead `renderPaneLayout` and `renderVTermAt`
   - (defer to Task 69 if preferred — task says keep renderSinglePane/findPaneRegion)

## Direction mapping

- PVertical (splits columns, left|right panes) → tank-layout Horizontal (splits width)
- PHorizontal (splits rows, top|bottom panes) → tank-layout Vertical (splits height)

## Border strategy

Borders are NOT part of the tank-layout tree. Instead:
1. Build layout WITHOUT borders (each pane gets its share minus border space)
2. Render the layout tree → CellGrid
3. Emit grid rows to stdout
4. Overdraw borders at the split positions (same logic as current code)

Actually, even simpler: build the layout with full space (no border accounting in the
layout tree). tank-layout's `Split` with the right ratio will divide the space. Then
overdraw borders on top. The current `findPaneRegion` already accounts for borders in
its own calculations, and we keep it as-is.

Wait — the current code gives each sub-pane space MINUS the border. If the layout tree
gives them the full space, the rendered cells will be in different positions than what
findPaneRegion expects. The layout tree ratio must match findPaneRegion's logic.

Current `renderPaneLayout` uses `w div 2` for PVertical (the first half), then reserves 1
col for border, and gives `w - w1 - 1` to the second pane. The tank-layout Split just
divides by ratio — there's no border column.

Approach: Use a 3-way split: left pane | 1-col border fill | right pane. The border fill
is a `Leaf (Fill '│' borderColor)`. This automatically handles the space. But border color
depends on which pane is active, which is a rendering concern.

Simplest approach: build the tank-layout tree for JUST the pane content (no borders). Use
adjusted ratios that account for border space. Then overdraw borders after emission.

For PVertical split in w-wide space with `w1 = w div 2`:
- Left pane: w1 cols
- Border: 1 col (overdraw after)
- Right pane: w - w1 - 1 cols
- Layout ratio: w1 / (w1 + (w - w1 - 1)) = w1 / (w - 1) ... but the layout's total width
  should be w - 1 (excluding border col)? No, the total is still w, but we lose 1 col.

Actually the cleanest: build a 3-node Split. Left pane takes w1/(w) ratio via
`Split Horizontal (w1/w) leftLeaf (Split Horizontal ((w-w1-1)/(w-w1)) borderLeaf rightLeaf)`.
Border leaf is `Leaf (Fill '│' Default)`.

Even simpler: just overdraw. The pane content will render "under" the border column, and
we overwrite that column with the border character. This wastes 1 col of pane content per
split but is the simplest approach that matches the existing behavior.

**Decision:** Overdraw approach. Build layout as if there are no borders (use full w/h, 0.5
ratio). Tank-layout's Split will give each side w/2 or h/2. Then overdraw borders. The fact
that pane content might render into the border column is fine — it gets overwritten.

Wait, this means the pane VTerm was resized to w1 (not w/2), so the CellGrid from VTerm
will be w1 wide, and tank-layout will place it in a w/2-wide space. That's fine — CellContent
stamps with `min rw sw`. The pane won't fill the border column (it's sized without it).

Hmm, but the ratio in the Layout tree needs to match how panes are actually sized. Let me
just use the same sizing logic as the current code: ratio that gives w1 to the left, 1 col
for border (via overdraw), and w-w1-1 to the right.

**Final decision:** Build the layout tree with ratios that produce the same pixel-perfect
sub-regions as `findPaneRegion`. The panes were resized to fit those regions. Then overdraw
borders. This means:
- For PVertical: ratio = (w div 2) / w ... but wait, findPaneRegion uses ratio from the
  PaneLayout, not w div 2. Let me re-read findPaneRegion.

findPaneRegion uses `floor (fromIntegral w * ratio) - 1` for w1 in PVertical. The stored
ratio is 0.5. So w1 = floor(w*0.5) - 1. The second pane starts at c + floor(w*0.5) with
width w - floor(w*0.5).

But renderPaneLayout uses `w div 2` for w1 and `w - w1 - 1` for w2. These don't match
findPaneRegion's formula! This is an existing inconsistency.

For this migration I'll match renderPaneLayout's existing logic (w div 2 / h div 2) since
that's what actually renders correctly.

Actually, I think the simplest approach that preserves exact behavior:
- Use the tank-layout tree solely for content rendering
- The width/height given to each leaf matches what the pane was resized to
- Don't worry about ratios in Split matching — just make the leaf CellGrids the right size

Since I'm building from VTerm grids that are already resized to the correct dimensions,
and tank-layout's CellContent stamps only `min rw sw` columns/rows, the content will be
correct as long as the Rect assigned to each leaf is big enough.

**Revised final approach:**
- buildLayout creates the Layout tree
- For Split, use adjusted ratio: leftWidth / totalWidth (accounting for border)
- renderLayout produces a grid
- emitGrid emits it
- drawPaneBorders overdraws borders
