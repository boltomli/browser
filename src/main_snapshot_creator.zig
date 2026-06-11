// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const lp = @import("lightpanda");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.c_allocator;

    var platform = try lp.js.Platform.init();
    defer platform.deinit();

    const snapshot = try lp.js.Snapshot.create();
    defer snapshot.deinit();

    var is_stdout = true;
    var file = std.Io.File.stdout();
    var args_iter = try init.minimal.args.iterateAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next(); // executable name
    if (args_iter.next()) |n| {
        is_stdout = false;
        file = try std.Io.Dir.cwd().createFile(std.Io.File.stderr().io, n, .{});
    }
    defer if (!is_stdout) {
        file.close(std.Io.File.stderr().io);
    };

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(std.Io.File.stderr().io, &buffer);
    try snapshot.write(&writer.interface);
    try writer.end();
}
