const std = @import("std");

const lp = @import("lightpanda");
const log = lp.log;
const js = lp.js;

const Element = @import("../browser/webapi/Element.zig");
const Selector = @import("../browser/webapi/selector/Selector.zig");
const protocol = @import("protocol.zig");
const Server = @import("Server.zig");

pub fn handleList(server: *Server, arena: std.mem.Allocator, req: protocol.Request) !void {
    _ = arena;
    const result = struct {
        tools: []const protocol.Tool,
    }{
        .tools = server.tools,
    };

    try sendResult(server, req.id.?, result);
}

const GotoParams = struct {
    url: [:0]const u8,
};

const SearchParams = struct {
    text: [:0]const u8,
};

const EvaluateParams = struct {
    script: [:0]const u8,
    url: ?[:0]const u8 = null,
};

const OverParams = struct {
    result: [:0]const u8,
};

const ToolStreamingText = struct {
    server: *Server,
    action: enum { markdown, links },

    pub fn jsonStringify(self: @This(), jw: *std.json.Stringify) !void {
        try jw.beginWriteRaw();
        try jw.writer.writeByte('"');
        var escaped = protocol.JsonEscapingWriter.init(jw.writer);
        const w = &escaped.writer;
        switch (self.action) {
            .markdown => lp.markdown.dump(self.server.page.document.asNode(), .{}, w, self.server.page) catch |err| {
                log.err(.mcp, "markdown dump failed", .{ .err = err });
            },
            .links => {
                if (Selector.querySelectorAll(self.server.page.document.asNode(), "a[href]", self.server.page)) |list| {
                    var first = true;
                    for (list._nodes) |node| {
                        if (node.is(Element.Html.Anchor)) |anchor| {
                            const href = anchor.getHref(self.server.page) catch |err| {
                                log.err(.mcp, "resolve href failed", .{ .err = err });
                                continue;
                            };

                            if (href.len > 0) {
                                if (!first) try w.writeByte('\n');
                                try w.writeAll(href);
                                first = false;
                            }
                        }
                    }
                } else |err| {
                    log.err(.mcp, "query links failed", .{ .err = err });
                }
            },
        }
        try jw.writer.writeByte('"');
        jw.endWriteRaw();
    }
};

pub fn handleCall(server: *Server, arena: std.mem.Allocator, req: protocol.Request) !void {
    if (req.params == null) {
        return sendError(server, req.id.?, -32602, "Missing params");
    }

    const CallParams = struct {
        name: []const u8,
        arguments: ?std.json.Value = null,
    };

    const call_params = std.json.parseFromValueLeaky(CallParams, arena, req.params.?, .{ .ignore_unknown_fields = true }) catch {
        var aw: std.Io.Writer.Allocating = .init(arena);
        std.json.Stringify.value(req.params.?, .{}, &aw.writer) catch {};
        const msg = std.fmt.allocPrint(arena, "Invalid params: {s}", .{aw.written()}) catch "Invalid params";
        return sendError(server, req.id.?, -32602, msg);
    };

    if (std.mem.eql(u8, call_params.name, "goto") or std.mem.eql(u8, call_params.name, "navigate")) {
        try handleGoto(server, arena, req.id.?, call_params.arguments);
    } else if (std.mem.eql(u8, call_params.name, "search")) {
        try handleSearch(server, arena, req.id.?, call_params.arguments);
    } else if (std.mem.eql(u8, call_params.name, "markdown")) {
        try handleMarkdown(server, arena, req.id.?, call_params.arguments);
    } else if (std.mem.eql(u8, call_params.name, "links")) {
        try handleLinks(server, arena, req.id.?, call_params.arguments);
    } else if (std.mem.eql(u8, call_params.name, "evaluate")) {
        try handleEvaluate(server, arena, req.id.?, call_params.arguments);
    } else if (std.mem.eql(u8, call_params.name, "over")) {
        try handleOver(server, arena, req.id.?, call_params.arguments);
    } else {
        return sendError(server, req.id.?, -32601, "Tool not found");
    }
}

fn handleGoto(server: *Server, arena: std.mem.Allocator, id: std.json.Value, arguments: ?std.json.Value) !void {
    const args = try parseParams(GotoParams, arena, arguments, server, id, "goto");
    try performGoto(server, args.url, id);

    const content = [_]struct { type: []const u8, text: []const u8 }{.{ .type = "text", .text = "Navigated successfully." }};
    try sendResult(server, id, .{ .content = &content });
}

fn handleSearch(server: *Server, arena: std.mem.Allocator, id: std.json.Value, arguments: ?std.json.Value) !void {
    const args = try parseParams(SearchParams, arena, arguments, server, id, "search");

    const component: std.Uri.Component = .{ .raw = args.text };
    var url_aw = std.Io.Writer.Allocating.init(arena);
    component.formatQuery(&url_aw.writer) catch {
        return sendError(server, id, -32603, "Internal error formatting query");
    };
    const url = std.fmt.allocPrintSentinel(arena, "https://duckduckgo.com/?q={s}", .{url_aw.written()}, 0) catch {
        return sendError(server, id, -32603, "Internal error formatting URL");
    };

    try performGoto(server, url, id);

    const content = [_]struct { type: []const u8, text: []const u8 }{.{ .type = "text", .text = "Search performed successfully." }};
    try sendResult(server, id, .{ .content = &content });
}

fn handleMarkdown(server: *Server, arena: std.mem.Allocator, id: std.json.Value, arguments: ?std.json.Value) !void {
    const MarkdownParams = struct {
        url: ?[:0]const u8 = null,
    };
    if (try parseParamsOptional(MarkdownParams, arena, arguments)) |args| {
        if (args.url) |u| {
            try performGoto(server, u, id);
        }
    }

    const result = struct {
        content: []const struct { type: []const u8, text: ToolStreamingText },
    }{
        .content = &.{.{
            .type = "text",
            .text = .{ .server = server, .action = .markdown },
        }},
    };
    try sendResult(server, id, result);
}

fn handleLinks(server: *Server, arena: std.mem.Allocator, id: std.json.Value, arguments: ?std.json.Value) !void {
    const LinksParams = struct {
        url: ?[:0]const u8 = null,
    };
    if (try parseParamsOptional(LinksParams, arena, arguments)) |args| {
        if (args.url) |u| {
            try performGoto(server, u, id);
        }
    }

    const result = struct {
        content: []const struct { type: []const u8, text: ToolStreamingText },
    }{
        .content = &.{.{
            .type = "text",
            .text = .{ .server = server, .action = .links },
        }},
    };
    try sendResult(server, id, result);
}

fn handleEvaluate(server: *Server, arena: std.mem.Allocator, id: std.json.Value, arguments: ?std.json.Value) !void {
    const args = try parseParams(EvaluateParams, arena, arguments, server, id, "evaluate");

    if (args.url) |url| {
        try performGoto(server, url, id);
    }

    var ls: js.Local.Scope = undefined;
    server.page.js.localScope(&ls);
    defer ls.deinit();

    const js_result = ls.local.compileAndRun(args.script, null) catch {
        const content = [_]struct { type: []const u8, text: []const u8 }{.{ .type = "text", .text = "Script evaluation failed." }};
        return sendResult(server, id, .{ .content = &content, .isError = true });
    };

    const str_result = js_result.toStringSliceWithAlloc(arena) catch "undefined";

    const content = [_]struct { type: []const u8, text: []const u8 }{.{ .type = "text", .text = str_result }};
    try sendResult(server, id, .{ .content = &content });
}

fn handleOver(server: *Server, arena: std.mem.Allocator, id: std.json.Value, arguments: ?std.json.Value) !void {
    const args = try parseParams(OverParams, arena, arguments, server, id, "over");

    const content = [_]struct { type: []const u8, text: []const u8 }{.{ .type = "text", .text = args.result }};
    try sendResult(server, id, .{ .content = &content });
}

fn parseParams(comptime T: type, arena: std.mem.Allocator, arguments: ?std.json.Value, server: *Server, id: std.json.Value, tool_name: []const u8) !T {
    if (arguments == null) {
        // We need to print the error message, so we need an allocator.
        // But we are in a helper, we should probably just return the error.
        // However, sendError sends the response.
        // Let's use a fixed buffer for the error message to avoid complex error handling.
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Missing arguments for {s}", .{tool_name}) catch "Missing arguments";
        try sendError(server, id, -32602, msg);
        return error.InvalidParams;
    }
    return std.json.parseFromValueLeaky(T, arena, arguments.?, .{ .ignore_unknown_fields = true }) catch {
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Invalid arguments for {s}", .{tool_name}) catch "Invalid arguments";
        try sendError(server, id, -32602, msg);
        return error.InvalidParams;
    };
}

fn parseParamsOptional(comptime T: type, arena: std.mem.Allocator, arguments: ?std.json.Value) !?T {
    if (arguments) |args_raw| {
        if (std.json.parseFromValueLeaky(T, arena, args_raw, .{ .ignore_unknown_fields = true })) |args| {
            return args;
        } else |_| {}
    }
    return null;
}

fn performGoto(server: *Server, url: [:0]const u8, id: std.json.Value) !void {
    _ = server.page.navigate(url, .{
        .reason = .address_bar,
        .kind = .{ .push = null },
    }) catch {
        try sendError(server, id, -32603, "Internal error during navigation");
        return error.NavigationFailed;
    };

    _ = server.session.wait(5000);
}

pub fn sendResult(server: *Server, id: std.json.Value, result: anytype) !void {
    const GenericResponse = struct {
        jsonrpc: []const u8 = "2.0",
        id: std.json.Value,
        result: @TypeOf(result),
    };
    try server.sendResponse(GenericResponse{
        .id = id,
        .result = result,
    });
}

pub fn sendError(server: *Server, id: std.json.Value, code: i64, message: []const u8) !void {
    try server.sendResponse(protocol.Response{
        .id = id,
        .@"error" = protocol.Error{
            .code = code,
            .message = message,
        },
    });
}
