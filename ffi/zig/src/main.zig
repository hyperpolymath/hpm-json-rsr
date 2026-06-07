// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// hpm-json-rsr — JSON parsing + escaping primitives.
//
// Built on `std.json.parseFromSlice`. Handles are heap-allocated little
// structs; the root handle owns a `Parsed(Value)` whose arena backs the
// entire parsed tree. Child handles (returned by `_object_get` and
// `_array_get`) point into that arena.

const std = @import("std");

const Value = std.json.Value;
const Parsed = std.json.Parsed;

/// A JSON value handle. The root handle (from `parse`) owns `parsed`
/// and is responsible for freeing the arena. Child handles set
/// `parsed = null` and just hold a pointer into the root's arena.
pub const HpmJsonValue = struct {
    allocator: std.mem.Allocator,
    parsed: ?Parsed(Value),
    value: *const Value,
};

/// Parse a JSON byte slice. Returns NULL on malformed input or
/// allocator failure.
export fn hpm_json_parse(src_ptr: ?[*]const u8, src_len: usize) ?*HpmJsonValue {
    const sp = src_ptr orelse return null;
    if (src_len == 0) return null;
    const allocator = std.heap.c_allocator;

    var parsed = std.json.parseFromSlice(Value, allocator, sp[0..src_len], .{}) catch return null;
    errdefer parsed.deinit();

    const handle = allocator.create(HpmJsonValue) catch {
        parsed.deinit();
        return null;
    };
    handle.* = .{
        .allocator = allocator,
        .parsed = parsed,
        .value = &handle.parsed.?.value,
    };
    return handle;
}

/// Free a value handle. Safe on NULL. Only the root handle frees the
/// underlying arena; child handles only free the wrapper.
export fn hpm_json_free(val: ?*HpmJsonValue) void {
    const v = val orelse return;
    if (v.parsed) |*p| p.deinit();
    v.allocator.destroy(v);
}

/// Returns the JSON type tag:
///   0=null 1=bool 2=int 3=float 4=string 5=array 6=object
///  -1 on null pointer.
export fn hpm_json_type(val: ?*HpmJsonValue) c_int {
    const v = val orelse return -1;
    return switch (v.value.*) {
        .null => 0,
        .bool => 1,
        .integer => 2,
        .float, .number_string => 3,
        .string => 4,
        .array => 5,
        .object => 6,
    };
}

/// Extract bool value. 1=true, 0=false, -1=type mismatch / null.
export fn hpm_json_bool(val: ?*HpmJsonValue) c_int {
    const v = val orelse return -1;
    return switch (v.value.*) {
        .bool => |b| @intFromBool(b),
        else => -1,
    };
}

/// Extract integer value. Returns `INT64_MIN` (0x8000_0000_0000_0000)
/// on type mismatch / null — that's a valid i64 value, but callers
/// should pair this with `hpm_json_type` first.
export fn hpm_json_int(val: ?*HpmJsonValue) i64 {
    const v = val orelse return std.math.minInt(i64);
    return switch (v.value.*) {
        .integer => |i| i,
        .float => |f| @intFromFloat(f),
        else => std.math.minInt(i64),
    };
}

/// Extract float value. Returns NaN on type mismatch / null.
export fn hpm_json_float(val: ?*HpmJsonValue) f64 {
    const v = val orelse return std.math.nan(f64);
    return switch (v.value.*) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => std.math.nan(f64),
    };
}

/// Copy a string value into `out`. Returns bytes written, or the
/// required size if `out` is NULL or `cap` is 0 (size-query), or -1
/// on type mismatch / `cap < required` / null val.
export fn hpm_json_string(val: ?*HpmJsonValue, out: ?[*]u8, cap: usize) isize {
    const v = val orelse return -1;
    const s = switch (v.value.*) {
        .string => |s| s,
        else => return -1,
    };
    if (out == null or cap == 0) return @intCast(s.len);
    if (cap < s.len) return -1;
    @memcpy(out.?[0..s.len], s);
    return @intCast(s.len);
}

/// Look up a key in an object value. Returns NULL on type mismatch,
/// missing key, or allocator failure.
export fn hpm_json_object_get(
    val: ?*HpmJsonValue,
    key_ptr: ?[*]const u8,
    key_len: usize,
) ?*HpmJsonValue {
    const v = val orelse return null;
    const kp = key_ptr orelse return null;
    if (key_len == 0) return null;
    const key = kp[0..key_len];

    const map = switch (v.value.*) {
        .object => |m| m,
        else => return null,
    };
    const child_value = map.getPtr(key) orelse return null;

    const handle = v.allocator.create(HpmJsonValue) catch return null;
    handle.* = .{
        .allocator = v.allocator,
        .parsed = null,
        .value = child_value,
    };
    return handle;
}

/// Length of an array value, or 0 on type mismatch / null.
export fn hpm_json_array_len(val: ?*HpmJsonValue) usize {
    const v = val orelse return 0;
    return switch (v.value.*) {
        .array => |a| a.items.len,
        else => 0,
    };
}

/// Index into an array value. NULL on type mismatch, out-of-bounds,
/// or allocator failure.
export fn hpm_json_array_get(val: ?*HpmJsonValue, idx: usize) ?*HpmJsonValue {
    const v = val orelse return null;
    const arr = switch (v.value.*) {
        .array => |a| a,
        else => return null,
    };
    if (idx >= arr.items.len) return null;

    const handle = v.allocator.create(HpmJsonValue) catch return null;
    handle.* = .{
        .allocator = v.allocator,
        .parsed = null,
        .value = &arr.items[idx],
    };
    return handle;
}

/// Escape a UTF-8 string for inclusion in a JSON literal. Does NOT
/// add surrounding quotes (caller does that). Returns bytes written,
/// or the required size if `out` is NULL or `cap` is 0 (size-query),
/// or -1 on `cap < required` / null src.
///
/// Handles RFC 8259 mandatory escapes: " \ \b \f \n \r \t, plus
/// \u00XX for control characters below 0x20. Non-ASCII bytes are
/// passed through unchanged (UTF-8 is valid JSON).
export fn hpm_json_escape_string(
    src_ptr: ?[*]const u8,
    src_len: usize,
    out: ?[*]u8,
    cap: usize,
) isize {
    const sp = src_ptr orelse return -1;
    const src = sp[0..src_len];

    var needed: usize = 0;
    for (src) |b| {
        needed += switch (b) {
            '"', '\\', '\n', '\r', '\t', 0x08, 0x0c => 2,
            else => if (b < 0x20) @as(usize, 6) else @as(usize, 1),
        };
    }

    if (out == null or cap == 0) return @intCast(needed);
    if (cap < needed) return -1;

    const o = out.?;
    var i: usize = 0;
    for (src) |b| {
        switch (b) {
            '"' => {
                o[i] = '\\';
                o[i + 1] = '"';
                i += 2;
            },
            '\\' => {
                o[i] = '\\';
                o[i + 1] = '\\';
                i += 2;
            },
            '\n' => {
                o[i] = '\\';
                o[i + 1] = 'n';
                i += 2;
            },
            '\r' => {
                o[i] = '\\';
                o[i + 1] = 'r';
                i += 2;
            },
            '\t' => {
                o[i] = '\\';
                o[i + 1] = 't';
                i += 2;
            },
            0x08 => {
                o[i] = '\\';
                o[i + 1] = 'b';
                i += 2;
            },
            0x0c => {
                o[i] = '\\';
                o[i + 1] = 'f';
                i += 2;
            },
            else => {
                if (b < 0x20) {
                    o[i] = '\\';
                    o[i + 1] = 'u';
                    o[i + 2] = '0';
                    o[i + 3] = '0';
                    const hi = (b >> 4) & 0x0f;
                    const lo = b & 0x0f;
                    o[i + 4] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
                    o[i + 5] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
                    i += 6;
                } else {
                    o[i] = b;
                    i += 1;
                }
            },
        }
    }
    return @intCast(i);
}

//==============================================================================
// Tests
//==============================================================================

test "parse + free flat object" {
    const src = "{\"token\":\"ghs_abc\",\"expires_at\":\"2026-05-28T12:00:00Z\"}";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);
    try std.testing.expectEqual(@as(c_int, 6), hpm_json_type(root));
}

test "parse malformed JSON returns null" {
    const src = "{not valid";
    try std.testing.expect(hpm_json_parse(src.ptr, src.len) == null);
}

test "parse empty / null inputs returns null" {
    try std.testing.expect(hpm_json_parse(null, 0) == null);
    const empty = "";
    try std.testing.expect(hpm_json_parse(empty.ptr, 0) == null);
}

test "object_get + string extract" {
    const src = "{\"token\":\"ghs_abc\"}";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);

    const key = "token";
    const child = hpm_json_object_get(root, key.ptr, key.len) orelse return error.LookupFailed;
    defer hpm_json_free(child);

    try std.testing.expectEqual(@as(c_int, 4), hpm_json_type(child));

    var buf: [32]u8 = undefined;
    const n = hpm_json_string(child, &buf, buf.len);
    try std.testing.expectEqualStrings("ghs_abc", buf[0..@intCast(n)]);
}

test "object_get missing key returns null" {
    const src = "{\"a\":1}";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);
    const key = "missing";
    try std.testing.expect(hpm_json_object_get(root, key.ptr, key.len) == null);
}

test "nested object lookup" {
    const src = "{\"installation\":{\"id\":12345,\"name\":\"acme\"}}";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);

    const inst_key = "installation";
    const inst = hpm_json_object_get(root, inst_key.ptr, inst_key.len) orelse return error.NestedFailed;
    defer hpm_json_free(inst);

    const id_key = "id";
    const id = hpm_json_object_get(inst, id_key.ptr, id_key.len) orelse return error.IdFailed;
    defer hpm_json_free(id);

    try std.testing.expectEqual(@as(c_int, 2), hpm_json_type(id));
    try std.testing.expectEqual(@as(i64, 12345), hpm_json_int(id));
}

test "array length + indexing" {
    const src = "[\"a\",\"b\",\"c\"]";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);

    try std.testing.expectEqual(@as(c_int, 5), hpm_json_type(root));
    try std.testing.expectEqual(@as(usize, 3), hpm_json_array_len(root));

    const child = hpm_json_array_get(root, 1) orelse return error.IndexFailed;
    defer hpm_json_free(child);

    var buf: [8]u8 = undefined;
    const n = hpm_json_string(child, &buf, buf.len);
    try std.testing.expectEqualStrings("b", buf[0..@intCast(n)]);
}

test "array out-of-bounds returns null" {
    const src = "[1,2,3]";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);
    try std.testing.expect(hpm_json_array_get(root, 10) == null);
}

test "bool / int / float extraction" {
    const src = "{\"b\":true,\"i\":42,\"f\":3.14,\"n\":null}";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);

    const bk = "b";
    const b = hpm_json_object_get(root, bk.ptr, bk.len).?;
    defer hpm_json_free(b);
    try std.testing.expectEqual(@as(c_int, 1), hpm_json_type(b));
    try std.testing.expectEqual(@as(c_int, 1), hpm_json_bool(b));

    const ik = "i";
    const i = hpm_json_object_get(root, ik.ptr, ik.len).?;
    defer hpm_json_free(i);
    try std.testing.expectEqual(@as(c_int, 2), hpm_json_type(i));
    try std.testing.expectEqual(@as(i64, 42), hpm_json_int(i));

    const fk = "f";
    const f = hpm_json_object_get(root, fk.ptr, fk.len).?;
    defer hpm_json_free(f);
    try std.testing.expectEqual(@as(c_int, 3), hpm_json_type(f));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), hpm_json_float(f), 0.001);

    const nk = "n";
    const n = hpm_json_object_get(root, nk.ptr, nk.len).?;
    defer hpm_json_free(n);
    try std.testing.expectEqual(@as(c_int, 0), hpm_json_type(n));
}

test "type mismatch in extractors" {
    const src = "{\"s\":\"hello\"}";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);
    const k = "s";
    const s = hpm_json_object_get(root, k.ptr, k.len).?;
    defer hpm_json_free(s);

    try std.testing.expectEqual(@as(c_int, -1), hpm_json_bool(s));
    // hpm_json_int on a string returns INT64_MIN
    try std.testing.expectEqual(std.math.minInt(i64), hpm_json_int(s));
    try std.testing.expect(std.math.isNan(hpm_json_float(s)));
}

test "string size-query" {
    const src = "\"hello world\"";
    const root = hpm_json_parse(src.ptr, src.len) orelse return error.ParseFailed;
    defer hpm_json_free(root);

    try std.testing.expectEqual(@as(isize, 11), hpm_json_string(root, null, 0));

    var small: [4]u8 = undefined;
    try std.testing.expectEqual(@as(isize, -1), hpm_json_string(root, &small, small.len));
}

test "escape_string basic" {
    const src = "hello \"world\"\n";
    var out: [32]u8 = undefined;
    const n = hpm_json_escape_string(src.ptr, src.len, &out, out.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings("hello \\\"world\\\"\\n", out[0..@intCast(n)]);
}

test "escape_string control chars" {
    const src = [_]u8{ 'a', 0x01, 'b' };
    var out: [16]u8 = undefined;
    const n = hpm_json_escape_string(&src, src.len, &out, out.len);
    try std.testing.expectEqualStrings("a\\u0001b", out[0..@intCast(n)]);
}

test "escape_string size-query" {
    const src = "a\tb";
    try std.testing.expectEqual(@as(isize, 4), hpm_json_escape_string(src.ptr, src.len, null, 0));
}

test "escape_string passes UTF-8 through" {
    const src = "café";
    var out: [16]u8 = undefined;
    const n = hpm_json_escape_string(src.ptr, src.len, &out, out.len);
    try std.testing.expectEqualStrings("café", out[0..@intCast(n)]);
}

test "null pointer safety" {
    try std.testing.expectEqual(@as(c_int, -1), hpm_json_type(null));
    try std.testing.expectEqual(@as(c_int, -1), hpm_json_bool(null));
    try std.testing.expectEqual(std.math.minInt(i64), hpm_json_int(null));
    try std.testing.expect(std.math.isNan(hpm_json_float(null)));
    try std.testing.expectEqual(@as(isize, -1), hpm_json_string(null, null, 0));
    try std.testing.expectEqual(@as(usize, 0), hpm_json_array_len(null));
    try std.testing.expect(hpm_json_array_get(null, 0) == null);
    const k = "x";
    try std.testing.expect(hpm_json_object_get(null, k.ptr, k.len) == null);
    hpm_json_free(null);
}
