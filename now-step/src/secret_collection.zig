// now: A Nix-based distributed command runner
// Copyright (C) 2026 Eric Rodrigues Pires
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
// more details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.
const SecretCollection = @This();

const std = @import("std");

allocator: std.mem.Allocator,
secrets: std.ArrayList([]const u8),

fn sortByLenDesc(_: void, a: []const u8, b: []const u8) bool {
    return a.len > b.len;
}

pub fn init(allocator: std.mem.Allocator, environ_map: *std.process.Environ.Map, secret_names: [][]const u8) !@This() {
    var secrets: std.ArrayList([]const u8) = .empty;
    errdefer secrets.deinit(allocator);

    for (secret_names) |name| {
        const secret_value = environ_map.get(name).?;
        var iterator = std.mem.splitScalar(u8, secret_value, '\n');
        while (iterator.next()) |secret_line| {
            if (secret_line.len > 0) {
                try secrets.append(allocator, secret_line);
            }
        }
    }

    const collection = @This(){
        .secrets = secrets,
        .allocator = allocator,
    };
    std.mem.sort([]const u8, collection.secrets.items, {}, sortByLenDesc);
    return collection;
}

pub fn deinit(
    self: *@This(),
) void {
    self.secrets.deinit(self.allocator);
}

pub fn redactLine(
    self: @This(),
    line: []const u8,
) ![]const u8 {
    var current: []const u8 = line;
    for (self.secrets.items) |secret| {
        if (std.mem.indexOf(u8, current, secret) == null) continue;
        current = try std.mem.replaceOwned(u8, self.allocator, current, secret, "***");
    }
    return current;
}
