const std = @import("std");
const Self = @import("diffmatchpatch.zig");

const MatchPrivate = @import("match_private.zig");

///Locate the best instance of 'pattern' in 'text' near 'loc'.
///Returns null if no match found.
pub fn matchMain(self: Self, text: []const u8, pattern: []const u8, loc: usize) (Self.MatchError || std.mem.Allocator.Error)!?usize {
    const index = @min(loc, text.len); // max with 0 is not needed since its unsigned

    if (std.mem.eql(u8, text, pattern)) {
        // shortcut
        return 0;
    } else if (text.len == 0) {
        // nothing to match
        return null;
    } else if (index + pattern.len <= text.len and std.mem.eql(u8, text[index .. index + pattern.len], pattern)) {
        // perfect match spot
        return @intCast(index);
    }
    // do fuzzy compare
    return self.matchBitap(text, pattern, index);
}

///Locate the best instance of 'pattern' in 'text' near 'loc' using the
///Bitap algorithm.  Returns null if no match found.
pub fn matchBitap(self: Self, text: []const u8, pattern: []const u8, loc: usize) (Self.MatchError || std.mem.Allocator.Error)!?usize {
    if (!(Self.match_max_bits == 0 or pattern.len <= Self.match_max_bits)) {
        return Self.MatchError.PatternTooLong;
    }

    // init alphabet
    const alphabet = MatchPrivate.match_alphabet(Self.MatchMaxContainer, pattern);

    // Highest score beyond which we give up.
    var score_threshold: f64 = @floatCast(self.match_threshold);
    // Is there a nearby exact match? (speedup)
    if (std.mem.indexOfPos(u8, text, loc, pattern)) |idx_best_loc| {
        score_threshold = @min(score_threshold, MatchPrivate.matchBitapScore(self, 0, @intCast(idx_best_loc), loc, pattern));
        // What about in the other direction? (speedup)
        if (std.mem.lastIndexOf(u8, text, pattern)) |last_best_loc| {
            score_threshold = @min(score_threshold, MatchPrivate.matchBitapScore(self, 0, @intCast(last_best_loc), loc, pattern));
        }
    }

    // init bit arrays
    const match_mask: u32 = @as(u32, 1) << @as(u5, @intCast(pattern.len - 1));
    var best_loc: ?usize = null;

    var bin_min: usize = 0;
    var bin_mid: usize = 0;
    var bin_max: usize = pattern.len + text.len;

    var last_rd: []u32 = undefined;
    var last_rd_set = false;
    var rd: []u32 = undefined;

    for (0..pattern.len) |d| {
        // Scan for the best match; each iteration allows for one more error.
        // Run a binary search to determine how far from 'loc' we can stray at
        // this error level.
        bin_min = 0;
        bin_mid = bin_max;
        while (bin_min < bin_mid) {
            if (MatchPrivate.matchBitapScore(self, @intCast(d), loc + bin_mid, loc, pattern) <= score_threshold) {
                bin_min = bin_mid;
            } else {
                bin_max = bin_mid;
            }
            bin_mid = (bin_max - bin_min) / 2 + bin_min;
        }
        // Use the result from this iteration as the maximum for the next.
        bin_max = bin_mid;
        var start: isize = @max(1, @as(i32, @intCast(loc)) - @as(i32, @intCast(bin_mid)) + 1);
        const finish: usize = @min(loc + bin_mid, text.len) + pattern.len;

        rd = try self.allocator.alloc(u32, finish + 2);

        rd[finish + 1] = (@as(u32, 1) << @as(u5, @intCast(d))) - 1;

        var j = finish;
        while (j >= start) : (j -= 1) {
            var char_match: u32 = 0;
            if (text.len <= j - 1) {
                // Out of range
                char_match = 0;
            } else {
                char_match = alphabet[text[j - 1]] orelse 0;
            }

            if (d == 0) {
                //First pass: exact match
                rd[j] = ((rd[j + 1] << 1) | 1) & char_match;
            } else {
                // subsequent passes: fuzzy match
                rd[j] = ((rd[j + 1] << 1) | 1) & char_match | (((last_rd[j + 1] | last_rd[j]) << 1) | 1) | last_rd[j + 1];
            }
            if ((rd[j] & match_mask) != 0) {
                const score = MatchPrivate.matchBitapScore(self, @intCast(d), j - 1, loc, pattern);
                // this match will most likely be better then any existing match, but double check
                if (score <= score_threshold) {
                    score_threshold = score;
                    best_loc = j - 1;
                    if (best_loc.? > loc) {
                        // when passing loc, dont exceed current distance from loc
                        start = @max(1, 2 * @as(i32, @intCast(loc)) - @as(i32, @intCast(best_loc.?)));
                    } else {
                        // already passed loc
                        break;
                    }
                }
            }
        }
        if (MatchPrivate.matchBitapScore(self, @intCast(d + 1), loc, loc, pattern) > score_threshold) {
            // no hope for a better match at greater error levels
            break;
        }

        if (last_rd_set) self.allocator.free(last_rd);
        last_rd = rd;
        last_rd_set = true;
    }
    if (last_rd.ptr != rd.ptr and last_rd_set) self.allocator.free(last_rd);
    self.allocator.free(rd);
    return best_loc;
}
