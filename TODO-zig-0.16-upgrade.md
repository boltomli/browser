# Zig 0.16 Upgrade TODO

## Status: ~90% done. Remaining are std library API changes.

## Completed (this session)
- [x] ArrayList default init: `= .{}` → `= .empty` (16 files)
- [x] std.Thread.Mutex → std.atomic.Mutex (ArenaPool, Env, crash_handler, Inbox)
- [x] PriorityQueue.add → push with allocator (Scheduler)
- [x] log.zig: simplified to std.debug.print
- [x] crash_handler: abort API, panic output simplified
- [x] datetime: clock_gettime → std.os.linux.clock_gettime
- [x] cli.zig: StructField.Attributes field names changed
- [x] string.zig: packed union @Vector → [12]u8 → needs further work
- [x] ArenaPool: MemoryPool.create now requires allocator

## Remaining Errors (compile-blocking)

### P0 - Must fix

- [ ] **string.zig:28** - `[12]u8` not allowed in packed union either
  - Packed unions can only contain types with bit-packed representation
  - Solution: remove `packed` from the union, or use raw bytes with `@bitCast`

- [ ] **cli.zig:289** - `std.process.argsWithAllocator` removed
  - New API: `Args.iterateAllocator(allocator)` from a `std.process.Args` struct
  - Need to get `Args` from `std.os.argv` or restructure the CLI parsing

- [ ] **Inbox.zig:39** - `std.Thread.Mutex` (missed one)

### P1 - Other known issues

- [ ] **@Vector in packed unions** - string.zig needs restructuring
- [ ] **std.Io.File.stderr().writerStreaming()** - crash_handler, log
- [ ] **std.debug.lockStdErr** - needs buffer parameter (log.zig done, others?)
- [ ] **V8 dependency** - local patches in zig-pkg/

### P2 - After compilation

- [ ] Run full test suite `make test`
- [ ] CI validation
- [ ] Performance regression check
