const std = @import("std");

///Encodes a string with URI-style % escaping.
pub fn encodeURI(writer: anytype, string: []const u8) @TypeOf(writer).Error!void {
    try std.Uri.Component.percentEncode(writer, string, encodeURIValid);
}
fn encodeURIValid(chr: u8) bool {
    return switch (chr) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '=', ':', ';', '\'', ',', '.', '/', '~', '!', '@', '#', '$', '&', '*', '(', ')', '_', '+', ' ', '?' => true,
        else => false,
    };
}

// TODO: add utf8 validation vefore this is used
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

///resizes a slice, returns the old size
pub fn resize(comptime T: type, allocator: std.mem.Allocator, slice: *[]T, new_len: usize) std.mem.Allocator.Error!usize {
    const len_start = slice.len;
    if (len_start == new_len) return len_start;
    if (allocator.resize(slice.*, new_len)) {
        slice.*.len = new_len;
        return len_start;
    }

    //failed to resize
    const new_slice = try allocator.alloc(T, new_len);
    @memcpy(new_slice[0..len_start], slice.*[0..@min(new_len, len_start)]);
    if (len_start < new_len) @memset(new_slice[len_start..], undefined);
    allocator.free(slice.*);
    slice.* = new_slice;
    return len_start;
    // TODO: tests
}

///Emulates the regex
///`^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@$`
pub fn matchPatchHeader(text: []const u8) ?struct { usize, ?usize, usize, ?usize } {
    if (!std.mem.startsWith(u8, text, "@@ -") or
        !std.mem.endsWith(u8, text, " @@"))
        return null;

    // strip '@@ -'
    var pointer: usize = 4;

    const digits: []const u8 = "0123456789";

    const digit1_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
    const digit1 = std.fmt.parseInt(usize, text[pointer..digit1_end_index], 10) catch return null;
    pointer = digit1_end_index;

    var digit2: ?usize = null;
    switch (text[pointer]) {
        ',' => {
            pointer += 1;
            const digit2_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
            digit2 = std.fmt.parseInt(usize, text[pointer..digit2_end_index], 10) catch return null;
            pointer = digit2_end_index;
        },
        ' ' => {},
        else => return null,
    }

    // check ` +`
    if (!std.mem.eql(u8, text[pointer .. pointer + 2], " +")) return null;
    pointer += 2;

    const digit3_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
    const digit3 = std.fmt.parseInt(usize, text[pointer..digit3_end_index], 10) catch return null;
    pointer = digit3_end_index;

    var digit4: ?usize = null;
    switch (text[pointer]) {
        ',' => {
            pointer += 1;
            const digit4_end_index = std.mem.indexOfNonePos(u8, text, pointer, digits) orelse return null;
            digit4 = std.fmt.parseInt(usize, text[pointer..digit4_end_index], 10) catch return null;
            pointer = digit4_end_index;
        },
        ' ' => {},
        else => return null,
    }

    // make sure that we are at the end only the ` @@` should be left
    if (pointer + 3 != text.len) return null;

    return .{ digit1, digit2, digit3, digit4 };
}

///Emulates the regex
///`\n\r?\n$`
pub fn blankLineEnd(text: []const u8) bool {
    if (text.len < 2) return false;

    //not \n$
    if (text[text.len - 1] != '\n') return false;
    //\n\n$
    if (text[text.len - 2] == '\n') return true;

    //\n\r\n$
    if (text.len >= 3 and text[text.len - 2] == '\r' and text[text.len - 3] == '\n') return true;
    return false;
}

///Emulates the regex
///`^\r?\n\r?\n`
pub fn blankLineStart(text: []const u8) bool {
    if (text.len < 2) return false;

    // fast paths
    //^\n\n
    if (text[0] == '\n' and text[1] == '\n') return true;
    //^\r\n\r\n
    if (text.len >= 4 and text[0] == '\r' and text[1] == '\n' and text[2] == '\r' and text[3] == '\n') return true;

    if (text.len < 3) return false;
    //^\n\r\n
    if (text[0] == '\n' and text[1] == '\r' and text[2] == '\n') return true;
    //^\r\n\n
    if (text[0] == '\r' and text[1] == '\n' and text[2] == '\n') return true;

    return false;
}

///returns true for all chars that the regex `\s` will match
pub fn isWhitespace(char: u8) bool {
    return switch (char) {
        ' ',
        '\t',
        '\r',
        '\n',
        0x0B, // \v vertical tab
        0x0C, // \f form feed
        => true,
        else => false,
    };
}

const testing = std.testing;

test "uri encode decode" {
    const TestCases = struct {
        text: []const u8,
        expect: []const u8,
    };
    var arraylist = std.ArrayList(u8).init(testing.allocator);
    defer arraylist.deinit();

    for ([_]TestCases{ .{
        .text = "[^A-Za-z0-9%-=;',./~!@#$%&*%(%)_%+ %?]",
        .expect = "%5B%5EA-Za-z0-9%25-=;',./~!@#$%25&*%25(%25)_%25+ %25?%5D",
    }, .{
        .text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ",
        .expect = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 - _ . ! ~ * ' ( ) ; / ? : @ & = + $ , # ",
    } }) |test_case| {
        arraylist.clearRetainingCapacity();
        try encodeURI(arraylist.writer(), test_case.text);
        try testing.expectEqualStrings(test_case.expect, arraylist.items);

        arraylist.items = std.Uri.percentDecodeInPlace(arraylist.items);
        try testing.expectEqualStrings(test_case.text, arraylist.items);
    }
}

test "patch regex header" {
    var result = matchPatchHeader("Some string");
    try testing.expect(result == null);

    result = matchPatchHeader("@@ -32,0 +53 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 32);
    try testing.expect(result.?[1] == 0);
    try testing.expect(result.?[2] == 53);
    try testing.expect(result.?[3] == null);

    result = matchPatchHeader("@@ -15 +20,42 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 15);
    try testing.expect(result.?[1] == null);
    try testing.expect(result.?[2] == 20);
    try testing.expect(result.?[3] == 42);

    result = matchPatchHeader("@@ -700,420 +5000,69 @@");
    try testing.expect(result != null);
    try testing.expect(result.?[0] == 700);
    try testing.expect(result.?[1] == 420);
    try testing.expect(result.?[2] == 5000);
    try testing.expect(result.?[3] == 69);

    result = matchPatchHeader("@@ -1,0 +3,-4 @@");
    try testing.expect(result == null);
}

test "blank line start regex" {
    try testing.expect(blankLineStart("\n\n"));
    try testing.expect(blankLineStart("\r\n\n"));
    try testing.expect(blankLineStart("\n\r\n"));
    try testing.expect(blankLineStart("\r\n\r\n"));

    try testing.expect(!blankLineStart("r\n\r\n"));
    try testing.expect(!blankLineStart("\rn\r\n"));
    try testing.expect(!blankLineStart("\r\nr\n"));
    try testing.expect(!blankLineStart("\r\n\rn"));

    try testing.expect(!blankLineStart("r\n\n"));
    try testing.expect(!blankLineStart("\rn\n"));
    try testing.expect(!blankLineStart("\r\nn"));

    try testing.expect(!blankLineStart("n\r\n"));
    try testing.expect(!blankLineStart("\nr\n"));
    try testing.expect(!blankLineStart("\n\rn"));

    try testing.expect(!blankLineStart("n\n"));
    try testing.expect(!blankLineStart("\nn"));

    try testing.expect(!blankLineStart("something random"));
    try testing.expect(blankLineStart("\n\nsomething random"));
    try testing.expect(blankLineStart("\r\n\r\nsomething random"));
}

test "blank line end regex" {
    try testing.expect(blankLineEnd("\n\n"));
    try testing.expect(blankLineEnd("\n\r\n"));

    try testing.expect(!blankLineEnd("n\r\n"));
    try testing.expect(!blankLineEnd("\nr\n"));
    try testing.expect(!blankLineEnd("\n\rn"));

    try testing.expect(!blankLineEnd("n\n"));
    try testing.expect(!blankLineEnd("\nn"));

    try testing.expect(!blankLineEnd("something random"));
    try testing.expect(blankLineEnd("something random\n\n"));
    try testing.expect(blankLineEnd("something random\r\n\r\n"));
}
