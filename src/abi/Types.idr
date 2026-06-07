-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| hpm-json-rsr — type declarations for the FFI boundary.

module HpmJson.ABI.Types

import Data.Buffer

%default total

--------------------------------------------------------------------------------
-- JSON type tags (match Zig FFI)
--------------------------------------------------------------------------------

public export
data JsonType
  = JsonNull
  | JsonBool
  | JsonInt
  | JsonFloat
  | JsonString
  | JsonArray
  | JsonObject
  | JsonInvalid   -- C side returned -1 (null pointer)

export
jsonTypeFromInt : Int -> JsonType
jsonTypeFromInt 0 = JsonNull
jsonTypeFromInt 1 = JsonBool
jsonTypeFromInt 2 = JsonInt
jsonTypeFromInt 3 = JsonFloat
jsonTypeFromInt 4 = JsonString
jsonTypeFromInt 5 = JsonArray
jsonTypeFromInt 6 = JsonObject
jsonTypeFromInt _ = JsonInvalid

--------------------------------------------------------------------------------
-- String / size result
--------------------------------------------------------------------------------

||| Outcome of `hpm_json_string` / `_escape_string`. The Zig side returns:
|||   ≥ 0  = bytes written (or required size if `out_cap == 0`)
|||   -1   = error (type mismatch / cap < required / null)
public export
data StringResult : Type where
  StringOk : (bytesWritten : Nat) -> StringResult
  StringError : StringResult

export
stringResultFromInt : Int -> StringResult
stringResultFromInt n =
  if n < 0
    then StringError
    else StringOk (cast n)
