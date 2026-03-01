const std = @import("std");

const lp = @import("lightpanda");
const log = lp.log;

const protocol = @import("protocol.zig");
const resources = @import("resources.zig");
const Server = @import("Server.zig");
const tools = @import("tools.zig");

pub fn processRequests(server: *Server) !void {
    var stdin_file = std.fs.File.stdin();
    var stdin_buf: [8192]u8 = undefined;
    var stdin = stdin_file.reader(&stdin_buf);

    server.is_running.store(true, .release);

    var arena: std.heap.ArenaAllocator = .init(server.allocator);
    defer arena.deinit();

    var msg_buf = std.Io.Writer.Allocating.init(server.allocator);
    defer msg_buf.deinit();

    while (server.is_running.load(.acquire)) {
        msg_buf.clearRetainingCapacity();
        const n = try stdin.interface.streamDelimiterLimit(&msg_buf.writer, '\n', .limited(1024 * 1024 * 10));

        var found_newline = true;
        _ = stdin.interface.discardDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => found_newline = false,
            else => return err,
        };

        if (n == 0 and !found_newline) break;

        const msg = msg_buf.written();
        if (msg.len == 0) continue;

        handleMessage(server, arena.allocator(), msg) catch |err| {
            log.warn(.mcp, "Error processing message", .{ .err = err });
            // We should ideally send a parse error response back, but it's hard to extract the ID if parsing failed entirely.
        };

        // 32KB: avoid reallocations while keeping memory footprint low.
        _ = arena.reset(.{ .retain_with_limit = 32 * 1024 });
    }
}

fn handleMessage(server: *Server, arena: std.mem.Allocator, msg: []const u8) !void {
    const parsed = std.json.parseFromSliceLeaky(protocol.Request, arena, msg, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        log.warn(.mcp, "JSON Parse Error", .{ .err = err, .msg = msg });
        return;
    };

    if (parsed.id == null) {
        // It's a notification
        if (std.mem.eql(u8, parsed.method, "notifications/initialized")) {
            log.info(.mcp, "Client Initialized", .{});
        }
        return;
    }

    if (std.mem.eql(u8, parsed.method, "initialize")) {
        try handleInitialize(server, parsed);
    } else if (std.mem.eql(u8, parsed.method, "resources/list")) {
        try resources.handleList(server, parsed);
    } else if (std.mem.eql(u8, parsed.method, "resources/read")) {
        try resources.handleRead(server, arena, parsed);
    } else if (std.mem.eql(u8, parsed.method, "tools/list")) {
        try tools.handleList(server, arena, parsed);
    } else if (std.mem.eql(u8, parsed.method, "tools/call")) {
        try tools.handleCall(server, arena, parsed);
    } else {
        try server.sendError(parsed.id.?, .MethodNotFound, "Method not found");
    }
}

fn handleInitialize(server: *Server, req: protocol.Request) !void {
    const result = protocol.InitializeResult{
        .protocolVersion = "2024-11-05",
        .capabilities = .{
            .logging = .{},
            .resources = .{ .subscribe = false, .listChanged = false },
            .tools = .{ .listChanged = false },
        },
        .serverInfo = .{
            .name = "lightpanda-mcp",
            .version = "0.1.0",
        },
    };

    try server.sendResult(req.id.?, result);
}
