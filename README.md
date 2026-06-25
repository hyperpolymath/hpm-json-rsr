<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->

Jonathan D.A. Jewell \<[j.d.a.jewell@open.ac](j.d.a.jewell@open.ac).uk\>
v0.1.0-dev, 2026-05-28 :toc: macro :toclevels: 2

**Minimal JSON parsing + string-escaping for the Hyperpolymath RSR
Standard (Idris2 ABI + Zig FFI). Built on `std.json.parseFromSlice`.**

Sibling to
[hpm-crypto-rsr](https://github.com/hyperpolymath/hpm-crypto-rsr) and
[hpm-http-client-rsr](https://github.com/hyperpolymath/hpm-http-client-rsr).
Together they form the bot integration layer.

<div id="toc">

</div>

# Status

`0.1.0-dev` — **parse + traverse + extract + escape, working in
scaffold.**

| Primitive | Status |
|----|----|
| `hpm_json_parse` / `_free` | Parse a JSON byte slice into an opaque value handle. |
| `hpm_json_type` | Detect the JSON type (null / bool / int / float / string / array / object). |
| `hpm_json_bool` / `_int` / `_float` / `_string` | Extract typed values. Type-mismatched calls fail safely. |
| `hpm_json_object_get` | Look up a key in an object value. Returns a child handle. |
| `hpm_json_array_len` / `_get` | Index into an array value. |
| `hpm_json_escape_string` | Escape a UTF-8 string for inclusion in JSON (no surrounding quotes). |

See <a href="ROADMAP.adoc" class="adoc">ROADMAP</a> for v0.2 (builder
API, streaming).

# Motivation

The OikosBot port parses GitHub API responses (`{"token":` `"…",`
`"expires_at":` `"…"}` etc.) and builds POST bodies (`{"body":` `"…"}`).
Inline-JS JSON.parse is banned by the language policy; this library
closes the gap.

See <a href="ABI-FFI-README.md" class="md">ABI-FFI-README</a> for the
RSR pattern.

# Build

```shell
cd ffi/zig
zig build           # builds libhpm_json.{so,a}
zig build test      # runs Zig test suite
```

# Lifetime model

All handles are heap-allocated little structs. The handle returned by
`hpm_json_parse` is the **root**; it owns the parsed arena. Handles
returned by `_object_get` / `_array_get` are **children** — they’re
lightweight wrappers over pointers into the root’s arena.

Callers should free both, but only the **root** free returns the arena.
Calling `_free` on a child handle simply destroys the wrapper.

Don’t use child handles after the root is freed.

# Licence

MPL-2.0. See [LICENSE](LICENSE).
