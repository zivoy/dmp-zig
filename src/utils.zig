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
