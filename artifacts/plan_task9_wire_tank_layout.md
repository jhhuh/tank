# Task 9: Wire tank-layout into tank

## Analysis

### Type mismatch between Terminal.hs Layout and tank-layout Layout

Terminal.hs has:
```haskell
data Layout = LPane Int | LSplit SplitDir Float Layout Layout
data SplitDir = Horizontal | Vertical
```

tank-layout has:
```haskell
data Layout = Leaf Content | Split Dir Float Layout Layout | Layers ... | Styled ...
data Dir = Horizontal | Vertical
```

These are **semantically different types**:
- Terminal.hs Layout = spatial arrangement of pane IDs (mutable workspace tree)
- tank-layout Layout = declarative rendering tree (content description)

Replacing one with the other would be wrong. Terminal.hs needs pane-ID-based layout
for split/remove/resize/cycle operations. tank-layout is for rendering content.

### Integration plan

1. **Add tank-layout dependency** to tank.cabal
2. **Rename Terminal.hs types** to avoid ambiguity: `Layout` -> `PaneLayout`, `SplitDir` stays (already matches `Dir` semantics)
3. **Migrate Overlay.hs** to use tank-layout for rendering instead of manual ANSI
4. **Keep Terminal.hs rendering** as-is for now (the VTerm cell rendering is tightly coupled to the terminal emulator's Cell type, which differs from tank-layout's Cell type)

### Why NOT replace Terminal.hs's renderLayout

Terminal.hs's `renderLayout` function renders VTerm grids into screen regions with
cursor positioning and border drawing. It operates on the terminal emulator's Cell type
(with Color256, flag-based attributes). tank-layout's Cell uses RGB colors and
bool-based attributes. Converting between them would add overhead and complexity
with no benefit since the terminal emulator output is already in the right format.

The overlay is the natural integration point: it builds a text box from scratch,
which maps perfectly to tank-layout's bordered/titled content model.

## Steps

1. Add `tank-layout` to tank.cabal build-depends -> verify: builds
2. Rename Terminal.hs `Layout`/`SplitDir` to `PaneLayout`/`SplitDir` to avoid collision -> verify: builds
3. Rewrite Overlay.hs renderOverlay to use tank-layout -> verify: builds, overlay still works
4. Run tests -> verify: all pass
