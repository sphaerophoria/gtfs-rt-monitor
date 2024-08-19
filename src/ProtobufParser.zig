const std = @import("std");

const ProtobufParser = @This();

it: []const u8,

pub fn next(self: *ProtobufParser) !?Output {
    if (self.it.len == 0) {
        return null;
    }

    const tag = try readTag(self.it[0]);
    self.it = self.it[1..];

    switch (tag.wire_type) {
        .len => {
            const ret = readVarint(self.it);
            self.it = self.it[ret.consumed_bytes..];

            if (ret.val > self.it.len) {
                return error.InvalidLen;
            }

            defer self.it = self.it[ret.val..];
            return .{
                .field = tag.field,
                .data = .{ .len = self.it[0..ret.val] },
            };
        },
        .varint => {
            const ret = readVarint(self.it);
            self.it = self.it[ret.consumed_bytes..];
            return .{
                .field = tag.field,
                .data = .{ .varint = ret.val },
            };
        },
        .i32 => {
            const val = self.it[0..];
            self.it = self.it[4..];
            return .{
                .field = tag.field,
                .data = .{ .i32 = std.mem.bytesToValue(i32, val) },
            };
        },
        else => {
            std.debug.print("unsupported wire type: {any}\n", .{tag.wire_type});
            @panic("ruh roh");
        },
    }
}

pub const OutputData = union(WireType) {
    varint: u64,
    i64: i64,
    len: []const u8,
    sgroup: void,
    egroup: void,
    i32: i32,

    pub fn asBuf(self: *const OutputData) ![]const u8 {
        if (self.* != .len) {
            return error.NotString;
        }

        return self.len;
    }

    pub fn asU64(self: *const OutputData) !u64 {
        if (self.* != .varint) {
            return error.NotVarInt;
        }

        return self.varint;
    }

    pub fn asF32(self: *const OutputData) !f32 {
        if (self.* != .i32) {
            return error.NotI32;
        }

        return @bitCast(self.i32);
    }
};

pub const Output = struct {
    field: u8,
    data: OutputData,
};

const WireType = enum(u8) {
    varint,
    i64,
    len,
    sgroup,
    egroup,
    i32,
};

const Tag = struct {
    field: u8,
    wire_type: WireType,
};

fn readTag(tag: u8) !Tag {
    const wire_type = try std.meta.intToEnum(WireType, tag & 0x7);
    return .{
        .field = tag >> 3,
        .wire_type = wire_type,
    };
}

const ParsedVarint = struct {
    val: u64,
    consumed_bytes: usize,
};

fn readVarint(buf: []const u8) ParsedVarint {
    var i: usize = 0;
    var shift: u6 = 0;
    var val: u64 = 0;
    while (true) {
        defer i += 1;
        const msb = buf[i] >> 7;

        val |= @as(u64, (buf[i] & 0x7f)) << shift;
        shift += 7;

        if (msb == 0) {
            break;
        }
    }

    return .{
        .val = val,
        .consumed_bytes = i,
    };
}
