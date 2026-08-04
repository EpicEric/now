// now: Nix-based distributed command runner
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

fn killChild(io: std.Io, child: *std.process.Child) void {
    child.kill(io);
    _ = child.wait(io) catch {};
}

fn waitForChild(child: *std.process.Child, io: std.Io, result: *std.process.Child.Term) void {
    waitForChildInner(child, io, result) catch |err| {
        std.log.err("waitForChild failed: {t}", .{err});
    };
}

fn waitForChildInner(child: *std.process.Child, io: std.Io, result: *std.process.Child.Term) !void {
    result.* = try child.wait(io);
}

fn pipe(reader: *std.Io.Reader, writer: *std.Io.Writer) void {
    pipeInner(reader, writer) catch |err| {
        std.log.err("pipe failed: {t}", .{err});
    };
}

fn pipeInner(reader: *std.Io.Reader, writer: *std.Io.Writer) !void {
    _ = try reader.streamRemaining(writer);
    try writer.flush();
}

fn takeLine(r: *std.Io.Reader) std.Io.Reader.DelimiterError![]u8 {
    var scanned: usize = 0;
    while (true) {
        const contents = r.buffer[r.seek..r.end];
        if (std.mem.findAnyPos(u8, contents, scanned, "\r\n")) |i| {
            if (contents[i] == '\n') {
                r.toss(i + 1);
                return contents[0..i];
            }
            if (i + 1 < contents.len) {
                if (contents[i + 1] == '\n') {
                    r.toss(i + 2);
                } else {
                    r.toss(i + 1);
                }
                return contents[0..i];
            }
            scanned = i;
        } else {
            scanned = contents.len;
        }
        if (contents.len == r.buffer.len) return error.StreamTooLong;
        r.fillMore() catch |err| switch (err) {
            error.ReadFailed => |e| return e,
            error.EndOfStream => {
                const rest = r.buffer[r.seek..r.end];
                if (rest.len != 0 and rest[rest.len - 1] == '\r') {
                    r.toss(rest.len);
                    return rest[0 .. rest.len - 1];
                }
                return error.EndOfStream;
            },
        };
    }
}

fn writeToStderr(mutex: *std.Io.Mutex, io: std.Io, reader: *std.Io.Reader, writer: *std.Io.Writer, secret_collection: now_step.SecretCollection) void {
    writeToStderrInner(mutex, io, reader, writer, secret_collection) catch |err| {
        std.log.err("writeToStderr failed: {t}", .{err});
    };
}

fn writeToStderrInner(mutex: *std.Io.Mutex, io: std.Io, reader: *std.Io.Reader, writer: *std.Io.Writer, secret_collection: now_step.SecretCollection) !void {
    while (true) {
        const line = takeLine(reader) catch |err| switch (err) {
            error.EndOfStream => {
                const rest = reader.buffered();
                if (rest.len > 0) {
                    const redacted = try secret_collection.redactLine(rest);
                    try mutex.lock(io);
                    defer mutex.unlock(io);
                    try writer.writeAll(redacted);
                    try writer.writeByte('\n');
                    try writer.flush();
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
                    try writer.writeByte('\n');
                    try writer.flush();
                }
                break;
            },
            else => return err,
        };

        const redacted_line = try secret_collection.redactLine(line);
        try mutex.lock(io);
        defer mutex.unlock(io);
        try writer.writeAll(redacted_line);
        try writer.writeByte('\n');
        try writer.flush();
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator: std.mem.Allocator = init.arena.allocator();

    var secret_names: std.ArrayList([]const u8) = .empty;
    defer secret_names.deinit(allocator);

    var arg_iterator = try init.minimal.args.iterateAllocator(allocator);
    defer arg_iterator.deinit();
    _ = arg_iterator.next().?; // Discard program name
    const derivation_or_flag = arg_iterator.next().?;
    var derivation: [:0]const u8 = undefined;
    const preserve_stdout = std.mem.eql(u8, derivation_or_flag, "--preserve-stdout");
    if (preserve_stdout) {
        derivation = arg_iterator.next().?;
    } else {
        derivation = derivation_or_flag;
    }
    while (arg_iterator.next()) |secret| {
        try secret_names.append(allocator, secret);
    }

    var secret_collection = try now_step.SecretCollection.init(allocator, init.environ_map, secret_names.items);
    defer secret_collection.deinit();

    var child_env = std.process.Environ.Map.init(allocator);
    defer child_env.deinit();
    var env_iterator = init.environ_map.iterator();
    while (env_iterator.next()) |entry| {
        try child_env.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    try child_env.put("CI", "true");
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
    errdefer killChild(io, &child);

    var child_stdout_buffer: [2048]u8 = undefined;
    var child_stdout_file = std.Io.File{ .handle = child.stdout.?.handle, .flags = .{ .nonblocking = false } };
    var child_stdout_file_reader = child_stdout_file.reader(init.io, &child_stdout_buffer);
    const child_stdout_reader = &child_stdout_file_reader.interface;

    var child_stderr_buffer: [2048]u8 = undefined;
    var child_stderr_file = std.Io.File{ .handle = child.stderr.?.handle, .flags = .{ .nonblocking = false } };
    var child_stderr_file_reader = child_stderr_file.reader(init.io, &child_stderr_buffer);
    const child_stderr_reader = &child_stderr_file_reader.interface;

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;

    var result: std.process.Child.Term = undefined;
    var mutex = std.Io.Mutex.init;
    var task_group = std.Io.Group.init;
    if (preserve_stdout) {
        var stdout_buffer: [512]u8 = undefined;
        var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
        const stdout_writer = &stdout_file_writer.interface;
        try task_group.concurrent(io, pipe, .{ child_stdout_reader, stdout_writer });
    } else {
        try task_group.concurrent(io, writeToStderr, .{ &mutex, io, child_stdout_reader, stderr_writer, secret_collection });
    }
    try task_group.concurrent(io, writeToStderr, .{ &mutex, io, child_stderr_reader, stderr_writer, secret_collection });
    try task_group.concurrent(io, waitForChild, .{ &child, io, &result });
    try task_group.await(io);

    std.process.exit(result.exited);
}
