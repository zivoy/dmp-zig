const std = @import("std");

///Encodes a string with URI-style % escaping.
pub fn encodeURI(writer: anytype, string: []const u8) @TypeOf(writer).Error!void {
    try std.Uri.Component.percentEncode(writer, string, encodeURIValid);
}
fn encodeURIValid(chr: u8) bool {
    return switch (chr) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '=', ';', '\'', ',', '.', '/', '~', '!', '@', '#', '$', '&', '*', '(', ')', '_', '+', ' ', '?' => true,
        else => false,
    };
}

pub fn utf8CountCodepointsPanic(text: []const u8) usize {
    return std.unicode.utf8CountCodepoints(text) catch |err| {
        var buf: [128]u8 = undefined;
        @panic(std.fmt.bufPrint(&buf, "error counting codepoints: {s}", .{@errorName(err)}) catch "codepoint count format err");
    };
}

pub fn getIdxOrNull(comptime T: type, arrayList: std.ArrayList(T), idx: usize) ?T {
    if (idx >= arrayList.items.len) return null;
    return arrayList.items[idx];
}

///Emulates the regex
///`^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@$`
pub fn matchPatchHeader(text: []const u8) !?struct { usize, ?usize, usize, ?usize } {
    if (!std.mem.startsWith(u8, text, "@@ -") or
        !std.mem.endsWith(u8, text, " @@"))
        return null;

    // strip '@@ -'
    var pointer: usize = 4;

    const digits: []const u8 = "0123456789";

    const digit1_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
    const digit1 = try std.fmt.parseInt(u8, text[pointer..digit1_end_index], 10);
    pointer = digit1_end_index;

    var digit2: ?usize = null;
    switch (text[pointer]) {
        ',' => {
            pointer += 1;
            const digit2_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
            digit2 = try std.fmt.parseInt(u8, text[pointer..digit2_end_index], 10);
            pointer = digit2_end_index;
        },
        ' ' => {},
        else => return null,
    }

    // check ` +`
    if (!std.mem.eql(u8, text[pointer .. pointer + 2], " +")) return null;
    pointer += 2;

    const digit3_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
    const digit3 = try std.fmt.parseInt(u8, text[pointer..digit3_end_index], 10);
    pointer = digit3_end_index;

    var digit4: ?usize = null;
    switch (text[pointer]) {
        ',' => {
            pointer += 1;
            const digit4_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
            digit4 = try std.fmt.parseInt(u8, text[pointer..digit4_end_index], 10);
            pointer = digit4_end_index;
        },
        ' ' => {},
        else => return null,
    }

    // make sure that we are at the end only the ` @@` should be left
    if (pointer + 3 != text.len) return null;

    return .{ digit1, digit2, digit3, digit4 };
}

const testing = std.testing;

test "uri encode decode" {
    const input = "[^A-Za-z0-9%-=;',./~!@#$%&*%(%)_%+ %?]";
    const expect = "%5B%5EA-Za-z0-9%25-=;',./~!@#$%25&*%25(%25)_%25+ %25?%5D";

    var arraylist = std.ArrayList(u8).init(testing.allocator);
    defer arraylist.deinit();
    try encodeURI(arraylist.writer(), input);
    try testing.expectEqualStrings(expect, arraylist.items);

    arraylist.items = std.Uri.percentDecodeInPlace(arraylist.items);
    try testing.expectEqualStrings(input, arraylist.items);
}

test "patch regex header" {
    var result = try matchPatchHeader("Some string");
    try testing.expect(result == null);

    result = try matchPatchHeader("@@ -32,0 +53 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 32);
    try testing.expect(result.?[1] == 0);
    try testing.expect(result.?[2] == 53);
    try testing.expect(result.?[3] == null);

    result = try matchPatchHeader("@@ -15 +20,42 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 15);
    try testing.expect(result.?[1] == null);
    try testing.expect(result.?[2] == 20);
    try testing.expect(result.?[3] == 42);
}
