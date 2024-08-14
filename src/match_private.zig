const std = @import("std");
const Self = @import("diffmatchpatch.zig");

///Compute and return the score for a match with n_errors and x location.
pub fn matchBitapScore(match_distance: u32, n_errors: u32, x: usize, loc: usize, pattern: []const u8) f64 {
    const accuracy: f64 = @as(f64, @floatFromInt(n_errors)) / @as(f64, @floatFromInt(pattern.len));
    const proximity: usize = @intCast(@abs(@as(isize, @intCast(loc)) - @as(isize, @intCast(x))));
    if (match_distance == 0) {
        if (proximity == 0) {
            return accuracy;
        }
        return 1;
    }
    return accuracy + (@as(f64, @floatFromInt(proximity)) / @as(f64, @floatFromInt(match_distance)));
}

///initialises the alphabet for the Bitap algorithm.
pub fn match_alphabet(comptime T: type, pattern: []const u8) [255]?T {
    var map: [255]?T = undefined;
    @memset(&map, null);
    for (pattern) |char| {
        // if (map[char] == 0) continue;
        map[char] = 0;
    }

    for (pattern, 0..) |char, i| {
        map[char] = map[char].? | (@as(T, 1) << @intCast(pattern.len - i - 1));
    }
    return map;
}
