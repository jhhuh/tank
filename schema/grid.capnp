@0xa3e8f1b2c4d56789;

# Tank Terminal Grid Schema
# Defines the CRDT grid state for terminal screen synchronization.

struct Color {
  union {
    default @0 :Void;
    index   @1 :UInt8;     # 256-color index
    rgb     @2 :RGB;
  }
}

struct RGB {
  r @0 :UInt8;
  g @1 :UInt8;
  b @2 :UInt8;
}

struct CellAttrs {
  bold      @0 :Bool;
  italic    @1 :Bool;
  underline @2 :Bool;
  reverse   @3 :Bool;
  blink     @4 :Bool;
  dim       @5 :Bool;
}

struct GridCell {
  codepoint @0 :UInt32;   # Unicode codepoint
  fg        @1 :Color;
  bg        @2 :Color;
  attrs     @3 :CellAttrs;
  epoch     @4 :UInt64;   # epoch tag for clear screen
  timestamp @5 :UInt64;   # Lamport timestamp
  replicaId @6 :Data;     # 16-byte UUID
}

struct CellUpdate {
  absLine   @0 :UInt64;   # absolute line number
  col       @1 :UInt16;   # column
  cell      @2 :GridCell;
}

struct GridDelta {
  union {
    # Cell content updates
    cells         @0 :List(CellUpdate);

    # Viewport position update
    viewport      @1 :ViewportUpdate;

    # Epoch (clear screen)
    epochUpdate   @2 :EpochUpdate;

    # Full snapshot (for initial sync or recovery)
    snapshot      @3 :GridSnapshot;
  }
}

struct ViewportUpdate {
  absLine   @0 :UInt64;   # new viewport top absolute line
  timestamp @1 :UInt64;
  replicaId @2 :Data;
}

struct EpochUpdate {
  epoch     @0 :UInt64;   # new epoch value
  timestamp @1 :UInt64;
  replicaId @2 :Data;
}

struct GridSnapshot {
  width       @0 :UInt16;
  height      @1 :UInt16;
  bufferAbove @2 :UInt16;
  bufferBelow @3 :UInt16;
  viewport    @4 :UInt64;  # viewport top absolute line
  epoch       @5 :UInt64;
  cells       @6 :List(CellUpdate);
}
