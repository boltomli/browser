# Zig 0.16 Upgrade TODO

## Status: Build system & language builtins done. Std library migration in progress.

## Remaining Tasks

### P0 - Blocking compilation

- [ ] **ArrayList default init** - `std.ArrayList(T) = .{}` no longer works (requires allocator)
  - Files: `Frame.zig`, `ScriptManagerBase.zig`, `AbortSignal.zig`, `Performance.zig`
  - Options: use `std.ArrayListUnmanaged(T)` or restructure to pass allocator at init

- [ ] **std.Io.File.stderr().writerStreaming()** - new I/O API requires `Io` parameter + buffer
  - Files: `crash_handler.zig`, `log.zig`
  - Use `std.debug.print()` or provide `Io` + buffer

- [ ] **std.debug.lockStdErr** removed
  - Files: `log.zig`
  - Find replacement in std.debug or use Io API

- [ ] **@Vector in packed unions** not allowed
  - Files: `string.zig`
  - Restructure the packed union to avoid @Vector field

### P1 - Likely blocking compilation (more files)

- [ ] **Other std.Io API changes** - many `std.fs.File.*` and `std.fs.cwd()` calls in src/ may need updating
  - Grep for `std.fs.File`, `std.fs.cwd()`, `std.fs.Dir` across src/

- [ ] **std.process API changes** - verify all ArgIterator -> Args.Iterator conversions complete

- [ ] **Panic/crash handler** - verify writer works with new Io API

### P2 - Non-blocking but needed before merge

- [ ] **V8 dependency build.zig** - local patches in `zig-pkg/` should be upstreamed or documented
  - Current patches: `Io.Dir.cwd()`, `statFile` options, `createDir`, timestamp `.nanoseconds`

- [ ] **Run full test suite** - `make test` to find remaining runtime issues

- [ ] **CI validation** - ensure GitHub Actions workflows pass with 0.16

### P3 - Nice to have

- [ ] **zig fmt** - run `zig fmt` on modified files

- [ ] **Performance regression check** - compare benchmark numbers
