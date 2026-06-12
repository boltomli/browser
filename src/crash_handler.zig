const std = @import("std");
const lp = @import("lightpanda");
const builtin = @import("builtin");

const IS_DEBUG = builtin.mode == .Debug;

const abort = std.process.abort;

fn findEnv(key: []const u8) ?[:0]const u8 {
    var i: usize = 0;
    while (std.c.environ[i] != null) : (i += 1) {
        const env = std.mem.sliceTo(std.c.environ[i].?, '=');
        if (std.mem.eql(u8, env, key)) {
            return std.mem.sliceTo(std.c.environ[i].? + env.len + 1, 0);
        }
    }
    return null;
}

// tracks how deep within a panic we're panicling
var panic_level: usize = 0;

// Locked to avoid interleaving panic messages from multiple threads.
var panic_mutex: std.atomic.Mutex = .unlocked;

// overwrite's Zig default panic handler
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, begin_addr: ?usize) noreturn {
    @branchHint(.cold);
    crash(msg, .{ .source = "global" }, begin_addr orelse @returnAddress());
}

pub noinline fn crash(
    reason: []const u8,
    args: anytype,
    begin_addr: usize,
) noreturn {
    @branchHint(.cold);

    nosuspend switch (panic_level) {
        0 => {
            panic_level = panic_level + 1;

            {
                while (!panic_mutex.tryLock()) {}
                defer panic_mutex.unlock();

                std.debug.print(
                    \\
                    \\Lightpanda has crashed. Please report the issue:
                    \\https://github.com/lightpanda-io/browser/issues
                    \\or let us know on discord: https://discord.gg/g24PtgD6
                    \\
                    \\
                    \\reason: {s}
                    \\OS: {s}
                    \\mode: {s}
                    \\version: {s}
                    \\
                , .{ reason, @tagName(builtin.os.tag), @tagName(builtin.mode), lp.build_config.version });

                std.debug.dumpCurrentStackTrace(.{ .first_address = begin_addr });
            }

            report(reason, begin_addr, args) catch {};
        },
        1 => {
            panic_level = 2;
            std.debug.print("panicked during a panic. Aborting.\n", .{});
        },
        else => {},
    };

    abort();
}

fn report(reason: []const u8, begin_addr: usize, args: anytype) !void {
    if (comptime IS_DEBUG) {
        return;
    }

    if (@import("telemetry/telemetry.zig").isDisabled()) {
        return;
    }

    var curl_path: [2048]u8 = undefined;
    const curl_path_len = curlPath(&curl_path) orelse return;

    var url_buffer: [4096]u8 = undefined;
    const url = blk: {
        var writer: std.Io.Writer = .fixed(&url_buffer);
        try writer.print("https://crash.lightpanda.io/c?v={s}&r=", .{lp.build_config.version_encoded});
        for (reason) |b| {
            switch (b) {
                'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_' => try writer.writeByte(b),
                ' ' => try writer.writeByte('+'),
                else => try writer.writeByte('!'), // some weird character, that we shouldn't have, but that'll we'll replace with a weird (bur url-safe) character
            }
        }

        try writer.writeByte(0);
        break :blk writer.buffered();
    };

    var body_buffer: [8192]u8 = undefined;
    const body = blk: {
        var writer: std.Io.Writer = .fixed(body_buffer[0..8191]); // reserve 1 space
        inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |f| {
            writer.writeAll(f.name ++ ": ") catch break;
            lp.log.writeValue(.pretty, @field(args, f.name), &writer) catch {};
            writer.writeByte('\n') catch {};
        }

        var addr_buf: [128]usize = undefined;
        const stack_trace = std.debug.captureCurrentStackTrace(.{ .first_address = begin_addr }, &addr_buf);
        var fmt: std.debug.FormatStackTrace = .{ .stack_trace = stack_trace };
        fmt.format(&writer) catch {};
        const written = writer.buffered();
        if (written.len == 0) {
            break :blk "???";
        }
        // Overwrite the last character with our null terminator
        // body_buffer always has to be > written
        body_buffer[written.len] = 0;
        break :blk body_buffer[0 .. written.len + 1];
    };

    var argv = [_:null]?[*:0]const u8{
        curl_path[0..curl_path_len :0],
        "-fsSL",
        "-H",
        "Content-Type: application/octet-stream",
        "--data-binary",
        body[0 .. body.len - 1 :0],
        url[0 .. url.len - 1 :0],
    };

    const result = std.c.fork();
    switch (result) {
        0 => {
            _ = std.c.close(0);
            _ = std.c.close(1);
            _ = std.c.close(2);
            _ = std.c.execve(argv[0].?, &argv, std.c.environ);
            std.c.exit(0);
        },
        else => return,
    }
}

fn curlPath(buf: []u8) ?usize {
    const path = findEnv("PATH") orelse return null;
    var it = std.mem.tokenizeScalar(u8, path, std.fs.path.delimiter);

    var fba = std.heap.FixedBufferAllocator.init(buf);
    const allocator = fba.allocator();

    const cwd = std.Io.Dir.cwd();
    while (it.next()) |p| {
        defer fba.reset();
        const full_path = std.fs.path.joinZ(allocator, &.{ p, "curl" }) catch continue;
        cwd.access(lp.io, full_path, .{}) catch continue;
        return full_path.len;
    }
    return null;
}
