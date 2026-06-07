<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk> -->

# hpm-json-rsr ABI/FFI Documentation

Built on `std.json.parseFromSlice` (Zig stdlib). No external deps.

## C ABI surface

```c
// Parse + lifecycle
hpm_json_value_t* hpm_json_parse(const uint8_t* src, size_t src_len);
void              hpm_json_free(hpm_json_value_t* val);

// Type detection. Returns:
//   0 = null
//   1 = bool
//   2 = integer
//   3 = float (or finite non-integer number)
//   4 = string
//   5 = array
//   6 = object
//  -1 = null pointer
int hpm_json_type(hpm_json_value_t* val);

// Typed extraction. -1 on type mismatch / null.
int     hpm_json_bool(hpm_json_value_t* val);
int64_t hpm_json_int(hpm_json_value_t* val);
double  hpm_json_float(hpm_json_value_t* val);

// Copy a string value into `out`. Returns bytes written, required
// size when `cap == 0` (size-query), or -1 on type mismatch / cap < req.
ssize_t hpm_json_string(hpm_json_value_t* val, uint8_t* out, size_t cap);

// Navigation. Returns NULL on type mismatch / key-not-found / out-of-bounds.
// Child handles are valid until the root is freed.
hpm_json_value_t* hpm_json_object_get(
    hpm_json_value_t* val, const uint8_t* key, size_t key_len);
size_t            hpm_json_array_len(hpm_json_value_t* val);
hpm_json_value_t* hpm_json_array_get(hpm_json_value_t* val, size_t idx);

// Escape a UTF-8 string for safe inclusion in a JSON literal. Does NOT
// add surrounding quotes (caller does that). Returns bytes written,
// required size when `cap == 0`, or -1 on cap < req / null pointer.
ssize_t hpm_json_escape_string(
    const uint8_t* src, size_t src_len, uint8_t* out, size_t cap);
```

## Types

| Code | Type | Notes |
|------|------|-------|
| 0 | null | `{"x": null}` |
| 1 | bool | `true` / `false` |
| 2 | integer | parsed as `i64` |
| 3 | float | `f64`; also "number_string" overflow values |
| 4 | string | UTF-8 bytes |
| 5 | array | use `_len` / `_get` |
| 6 | object | use `_object_get` |

## Limits

- Max parsed value depth: defaults to `std.json.default_max_value_len`
- Source bytes: practically unbounded (limited by allocator)
