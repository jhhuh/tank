@0xb7c5e3a9f1d24680;

# Tank Protocol Schema
# This is the source of truth for the tank wire protocol.

using Grid = import "grid.capnp";

struct MessageEnvelope {
  version   @0 :UInt16;
  sourceId  @1 :Data;     # 16-byte UUID of source plug
  target    @2 :Target;
  sequence  @3 :UInt64;   # Lamport clock
  payload   @4 :Message;
}

struct Target {
  union {
    cell      @0 :Data;     # 16-byte CellId UUID
    plug      @1 :Data;     # 16-byte PlugId UUID
    broadcast @2 :Void;
  }
}

struct PlugCapabilities {
  terminal   @0 :Bool;
  operator   @1 :Bool;
  devshell   @2 :Bool;
  processMgr @3 :Bool;
}

struct PlugInfo {
  id           @0 :Data;   # 16-byte UUID
  name         @1 :Text;
  capabilities @2 :PlugCapabilities;
}

struct CellInfo {
  id        @0 :Data;      # 16-byte UUID
  directory @1 :Text;
}

struct Message {
  union {
    # Plug lifecycle
    plugRegister      @0  :PlugInfo;
    plugRegistered    @1  :Data;       # PlugId
    plugDeregister    @2  :Data;       # PlugId

    # Cell lifecycle
    cellCreate        @3  :CellCreate;
    cellDestroy       @4  :Data;       # CellId
    cellAttach        @5  :CellAttach;
    cellDetach        @6  :CellDetach;

    # State sync (CRDT)
    stateUpdate       @7  :StateUpdate;

    # Scrollback
    fetchLines        @8  :FetchLines;
    fetchLinesResp    @9  :FetchLinesResponse;

    # Queries
    listCells         @10 :Void;
    listCellsResp     @11 :List(CellInfo);

    # Terminal I/O
    input             @12 :TerminalIO;
    output            @13 :TerminalIO;

    # Errors
    error             @14 :Text;
  }
}

struct CellCreate {
  cellId    @0 :Data;      # 16-byte UUID
  directory @1 :Text;
  shell     @2 :Text;      # shell command to spawn
}

struct CellAttach {
  cellId @0 :Data;
  plugId @1 :Data;
}

struct CellDetach {
  cellId @0 :Data;
  plugId @1 :Data;
}

struct StateUpdate {
  cellId @0 :Data;
  delta  @1 :Grid.GridDelta;
}

struct FetchLines {
  cellId   @0 :Data;
  fromLine @1 :UInt64;
  toLine   @2 :UInt64;
}

struct FetchLinesResponse {
  cellId @0 :Data;
  lines  @1 :List(ScrollbackLine);
}

struct ScrollbackLine {
  absLine @0 :UInt64;
  content @1 :Text;
}

struct TerminalIO {
  cellId @0 :Data;
  data   @1 :Data;        # raw bytes
}
