# Zig 0.16 Upgrade TODO

## Status: ~70% done. Many more std lib renames remaining.

## Remaining Errors (~25 unique)

### std lib renames (batch-fixable)
- [ ] `std.meta.intToEnum` -> `@enumFromInt` (7 files: DragEvent, KeyboardEvent, MouseEvent, PointerEvent, WheelEvent)
- [ ] `std.time.milliTimestamp()` removed (File.zig)
- [ ] `std.time.timestamp()` removed (HTMLDocument.zig, CookieStore.zig)
- [ ] `std.mem.trimRight` -> `trimEnd` (Mime.zig, missed one)
- [ ] `std.Thread.Condition` removed (Network.zig)

### struct/union field changes
- [ ] `std.Thread.Mutex = .{}` -> `std.atomic.Mutex = .unlocked` (Network.zig:130 Condition)
- [ ] `MemoryPool.init(allocator)` -> `MemoryPool.empty` or new init (EventManagerBase.zig)
- [ ] `ArrayList` missing `.empty` for struct fields (ScriptManager, PerformanceObserver, Notification)
- [ ] `ArrayList` no longer has `.allocator` field (HTMLDocument.zig:241)
- [ ] `cli.zig:612` - struct field `obey_robots` missing (union type issue)

### pointer/opaque issues
- [ ] `@cImport` opaque struct `Data` can't be indexable (Context.zig:316, Local.zig:139)
- [ ] `main_snapshot_creator.zig:38` - `Io.File` has no `io` field

### Other
- [ ] `std.posix.clock_gettime` type issues
