const std = @import("std");

const lp = @import("lightpanda");

const App = @import("../App.zig");
const HttpClient = @import("../http/Client.zig");
const protocol = @import("protocol.zig");
const Self = @This();

allocator: std.mem.Allocator,
app: *App,

http_client: *HttpClient,
notification: *lp.Notification,
browser: *lp.Browser,
session: *lp.Session,
page: *lp.Page,

tools: []const protocol.Tool,
resources: []const protocol.Resource,

is_running: std.atomic.Value(bool) = .init(false),

stdout_mutex: std.Thread.Mutex = .{},

pub fn init(allocator: std.mem.Allocator, app: *App) !*Self {
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    self.allocator = allocator;
    self.app = app;

    self.http_client = try app.http.createClient(allocator);
    errdefer self.http_client.deinit();

    self.notification = try .init(allocator);
    errdefer self.notification.deinit();

    self.browser = try allocator.create(lp.Browser);
    errdefer allocator.destroy(self.browser);
    self.browser.* = try .init(app, .{ .http_client = self.http_client });
    errdefer self.browser.deinit();

    self.session = try self.browser.newSession(self.notification);
    self.page = try self.session.createPage();

    self.tools = try initTools(allocator);
    self.resources = try initResources(allocator);

    return self;
}

fn initTools(allocator: std.mem.Allocator) ![]const protocol.Tool {
    const tools = try allocator.alloc(protocol.Tool, 6);
    errdefer allocator.free(tools);

    tools[0] = .{
        .name = "goto",
        .description = "Navigate to a specified URL and load the page in memory so it can be reused later for info extraction.",
        .inputSchema = try std.json.parseFromSliceLeaky(std.json.Value, allocator,
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "url": { "type": "string", "description": "The URL to navigate to, must be a valid URL." }
            \\  },
            \\  "required": ["url"]
            \\}
        , .{}),
    };
    tools[1] = .{
        .name = "search",
        .description = "Use a search engine to look for specific words, terms, sentences. The search page will then be loaded in memory.",
        .inputSchema = try std.json.parseFromSliceLeaky(std.json.Value, allocator,
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "text": { "type": "string", "description": "The text to search for, must be a valid search query." }
            \\  },
            \\  "required": ["text"]
            \\}
        , .{}),
    };
    tools[2] = .{
        .name = "markdown",
        .description = "Get the page content in markdown format. If a url is provided, it navigates to that url first.",
        .inputSchema = try std.json.parseFromSliceLeaky(std.json.Value, allocator,
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "url": { "type": "string", "description": "Optional URL to navigate to before fetching markdown." }
            \\  }
            \\}
        , .{}),
    };
    tools[3] = .{
        .name = "links",
        .description = "Extract all links in the opened page. If a url is provided, it navigates to that url first.",
        .inputSchema = try std.json.parseFromSliceLeaky(std.json.Value, allocator,
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "url": { "type": "string", "description": "Optional URL to navigate to before extracting links." }
            \\  }
            \\}
        , .{}),
    };
    tools[4] = .{
        .name = "evaluate",
        .description = "Evaluate JavaScript in the current page context. If a url is provided, it navigates to that url first.",
        .inputSchema = try std.json.parseFromSliceLeaky(std.json.Value, allocator,
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "script": { "type": "string" },
            \\    "url": { "type": "string", "description": "Optional URL to navigate to before evaluating." }
            \\  },
            \\  "required": ["script"]
            \\}
        , .{}),
    };
    tools[5] = .{
        .name = "over",
        .description = "Used to indicate that the task is over and give the final answer if there is any. This is the last tool to be called in a task.",
        .inputSchema = try std.json.parseFromSliceLeaky(std.json.Value, allocator,
            \\{
            \\  "type": "object",
            \\  "properties": {
            \\    "result": { "type": "string", "description": "The final result of the task." }
            \\  },
            \\  "required": ["result"]
            \\}
        , .{}),
    };

    return tools;
}

fn initResources(allocator: std.mem.Allocator) ![]const protocol.Resource {
    const resources = try allocator.alloc(protocol.Resource, 2);
    errdefer allocator.free(resources);

    resources[0] = .{
        .uri = "mcp://page/html",
        .name = "Page HTML",
        .description = "The serialized HTML DOM of the current page",
        .mimeType = "text/html",
    };
    resources[1] = .{
        .uri = "mcp://page/markdown",
        .name = "Page Markdown",
        .description = "The token-efficient markdown representation of the current page",
        .mimeType = "text/markdown",
    };

    return resources;
}

pub fn deinit(self: *Self) void {
    self.is_running.store(false, .seq_cst);

    self.browser.deinit();
    self.allocator.destroy(self.browser);
    self.notification.deinit();
    self.http_client.deinit();

    self.allocator.free(self.tools);
    self.allocator.free(self.resources);

    self.allocator.destroy(self);
}

pub fn sendResponse(self: *Self, response: anytype) !void {
    self.stdout_mutex.lock();
    defer self.stdout_mutex.unlock();

    var stdout_file = std.fs.File.stdout();
    var stdout_buf: [8192]u8 = undefined;
    var stdout = stdout_file.writer(&stdout_buf);
    try std.json.Stringify.value(response, .{ .emit_null_optional_fields = false }, &stdout.interface);
    try stdout.interface.writeByte('\n');
    try stdout.interface.flush();
}

pub fn sendResult(self: *Self, id: std.json.Value, result: anytype) !void {
    const GenericResponse = struct {
        jsonrpc: []const u8 = "2.0",
        id: std.json.Value,
        result: @TypeOf(result),
    };
    try self.sendResponse(GenericResponse{
        .id = id,
        .result = result,
    });
}

pub fn sendError(self: *Self, id: std.json.Value, code: protocol.ErrorCode, message: []const u8) !void {
    try self.sendResponse(protocol.Response{
        .id = id,
        .@"error" = protocol.Error{
            .code = @intFromEnum(code),
            .message = message,
        },
    });
}
