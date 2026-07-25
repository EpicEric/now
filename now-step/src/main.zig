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

const std = @import("std");
const builtin = @import("builtin");
const now_step = @import("now_step");

fn kill_child(io: std.Io, child: *std.process.Child) void {
    child.kill(io);
    _ = child.wait(io) catch {};
}

fn write_to_stdout(mutex: *std.Io.Mutex, io: std.Io, reader: *std.Io.Reader, writer: *std.Io.Writer, secret_collection: now_step.SecretCollection) void {
    write_to_stdout_inner(mutex, io, reader, writer, secret_collection) catch |err| {
        std.log.err("write_to_stdout failed: {t}", .{err});
    };
}

fn write_to_stdout_inner(mutex: *std.Io.Mutex, io: std.Io, reader: *std.Io.Reader, writer: *std.Io.Writer, secret_collection: now_step.SecretCollection) !void {
    while (true) {
        const line = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                const rest = reader.buffered();
                if (rest.len > 0) {
                    const redacted = try secret_collection.redactLine(rest);
                    try mutex.lock(io);
                    defer mutex.unlock(io);
                    try writer.writeAll(redacted);
                }
                break;
            },
            error.ReadFailed => {
                const rest = reader.buffered();
                if (rest.len > 0) {
                    const redacted = try secret_collection.redactLine(rest);
                    try mutex.lock(io);
                    defer mutex.unlock(io);
                    try writer.writeAll(redacted);
                }
                break;
            },
            else => return err,
        };

        const redacted_line = try secret_collection.redactLine(line);
        try mutex.lock(io);
        defer mutex.unlock(io);
        try writer.writeAll(redacted_line);
        try writer.flush();
    }
    try mutex.lock(io);
    defer mutex.unlock(io);
    try writer.flush();
}

pub fn main(init: std.process.Init) !void {
    const allocator: std.mem.Allocator = init.arena.allocator();

    var secret_names: std.ArrayList([]const u8) = .empty;
    defer secret_names.deinit(allocator);

    var arg_iterator = try init.minimal.args.iterateAllocator(allocator);
    defer arg_iterator.deinit();
    _ = arg_iterator.next().?;
    const derivation = arg_iterator.next().?;
    while (arg_iterator.next()) |secret| {
        try secret_names.append(allocator, secret);
    }

    var secret_collection = try now_step.SecretCollection.init(allocator, init.environ_map, secret_names.items);
    defer secret_collection.deinit();

    var child_env = std.process.Environ.Map.init(allocator);
    defer child_env.deinit();
    var env_iterator = init.environ_map.iterator();
    while (env_iterator.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "NO_COLOR") and !std.mem.eql(u8, entry.key_ptr.*, "COLORFGBG")) {
            try child_env.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
    try child_env.put("CI", "true");
    try child_env.put("FORCE_COLOR", "1");
    try child_env.put("CLICOLOR_FORCE", "1");
    try child_env.put("TERM", "xterm-256color");

    var io_impl: std.Io.Threaded = .init(allocator, .{});
    defer io_impl.deinit();
    const io = io_impl.io();

    var child = try std.process.spawn(io, .{
        .argv = &.{derivation},
        .environ_map = &child_env,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    errdefer kill_child(io, &child);

    var child_stdout_buffer: [2048]u8 = undefined;
    var child_stdout_file = std.Io.File{ .handle = child.stdout.?.handle, .flags = .{ .nonblocking = false } };
    var child_stdout_file_reader = child_stdout_file.reader(init.io, &child_stdout_buffer);
    const child_stdout_reader = &child_stdout_file_reader.interface;

    var child_stderr_buffer: [2048]u8 = undefined;
    var child_stderr_file = std.Io.File{ .handle = child.stderr.?.handle, .flags = .{ .nonblocking = false } };
    var child_stderr_file_reader = child_stderr_file.reader(init.io, &child_stderr_buffer);
    const child_stderr_reader = &child_stderr_file_reader.interface;

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var mutex = std.Io.Mutex.init;
    var task_group = std.Io.Group.init;
    try task_group.concurrent(io, write_to_stdout, .{ &mutex, io, child_stdout_reader, stdout_writer, secret_collection });
    try task_group.concurrent(io, write_to_stdout, .{ &mutex, io, child_stderr_reader, stdout_writer, secret_collection });
    try task_group.await(io);

    const result = try child.wait(init.io);
    std.process.exit(result.exited);
}
