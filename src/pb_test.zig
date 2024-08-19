const std = @import("std");
const ProtobufParser = @import("ProtobufParser.zig");
const Allocator = std.mem.Allocator;

const FeedHeader = struct {
    gtfs_realtime_version: []const u8,
    incrementality: u8,
    timestamp: u64,

    pub fn parse(buf: []const u8) !FeedHeader {
        var parser = ProtobufParser{ .it = buf };

        var gtfs_realtime_version: ?[]const u8 = null;
        var incrementality: ?u64 = null;
        var timestamp: ?u64 = null;

        while (try parser.next()) |item| {
            switch (item.field) {
                1 => gtfs_realtime_version = try item.data.asBuf(),
                2 => incrementality = try item.data.asU64(),
                3 => timestamp = try item.data.asU64(),
                else => {
                    std.log.warn("Unhandled feed header field: {d}", .{item.field});
                },
            }
        }

        return .{
            .gtfs_realtime_version = gtfs_realtime_version orelse return error.NoGtfsRealtime,
            .incrementality = @intCast(incrementality orelse return error.NoIncrementality),
            .timestamp = timestamp orelse return error.NoTimestamp,
        };
    }
};

const Position = struct {
    latitude: f32,
    longitude: f32,

    pub fn parse(buf: []const u8) !Position {
        var parser = ProtobufParser{ .it = buf };

        var latitude: ?f32 = null;
        var longitude: ?f32 = null;

        while (try parser.next()) |val| {
            switch (val.field) {
                1 => latitude = try val.data.asF32(),
                2 => longitude = try val.data.asF32(),
                else => {
                    std.log.warn("Got Position field with id: {d}", .{val.field});
                },
            }
        }
        return .{
            .latitude = latitude orelse return error.NoLatitude,
            .longitude = longitude orelse return error.NoLongitude,
        };
    }
};

const VehiclePosition = struct {
    position: ?Position,

    pub fn parse(buf: []const u8) !VehiclePosition {
        var parser = ProtobufParser{ .it = buf };
        var position: ?Position = null;

        while (try parser.next()) |val| {
            switch (val.field) {
                2 => position = try Position.parse(try val.data.asBuf()),
                else => {
                    std.log.warn("Got VehiclePosition field with id: {d}", .{val.field});
                },
            }
        }
        return .{
            .position = position,
        };
    }
};

const FeedEntity = struct {
    id: []const u8,
    vehicle_position: ?VehiclePosition,

    pub fn parse(alloc: Allocator, buf: []const u8) !FeedEntity {
        _ = alloc;
        var parser = ProtobufParser{ .it = buf };
        var id: ?[]const u8 = null;
        var vehicle_position: ?VehiclePosition = null;

        while (try parser.next()) |val| {
            switch (val.field) {
                1 => id = try val.data.asBuf(),
                4 => vehicle_position = try VehiclePosition.parse(try val.data.asBuf()),
                else => {
                    std.log.warn("Got entity with id: {d}", .{val.field});
                },
            }
        }
        return .{
            .id = id orelse return error.NoId,
            .vehicle_position = vehicle_position,
        };
    }
};

const FeedMessage = struct {
    header: FeedHeader,
    entities: []FeedEntity,

    pub fn parse(alloc: Allocator, buf: []const u8) !FeedMessage {
        var parser = ProtobufParser{ .it = buf };

        var header: ?FeedHeader = null;
        var entities = std.ArrayList(FeedEntity).init(alloc);
        defer entities.deinit();

        while (try parser.next()) |val| {
            switch (val.field) {
                1 => header = try FeedHeader.parse(try val.data.asBuf()),
                2 => try entities.append(try FeedEntity.parse(alloc, try val.data.asBuf())),
                else => {},
            }
        }

        return .{
            .header = header orelse return error.NoHeader,
            .entities = try entities.toOwnedSlice(),
        };
    }

    pub fn deinit(self: *FeedMessage, alloc: Allocator) void {
        alloc.free(self.entities);
    }
};

const Args = struct {
    pb: []const u8,

    pub fn parse(alloc: Allocator) !Args {
        var args = try std.process.argsWithAllocator(alloc);
        const process_name = args.next() orelse "pb_test";

        const pb = args.next() orelse {
            help(process_name);
        };

        return .{
            .pb = pb,
        };
    }

    fn help(process_name: []const u8) noreturn {
        const stderr = std.io.getStdErr();
        const writer = stderr.writer();
        writer.print("{s} [INPUT FILE]\n", .{process_name}) catch {};
        std.process.exit(1);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    const args = try Args.parse(alloc);

    const f = try std.fs.cwd().openFile(args.pb, .{});

    const buf = try f.readToEndAlloc(alloc, 1_000_000_000);
    defer alloc.free(buf);

    var message = try FeedMessage.parse(alloc, buf);
    defer message.deinit(alloc);

    for (message.entities) |entity| {
        if (entity.vehicle_position) |vp| {
            if (vp.position) |p| {
                std.debug.print("Vehicle position update: {d}, {d}\n", .{ p.latitude, p.longitude });
            }
        }
    }
}
