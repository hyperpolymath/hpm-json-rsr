||| hpm-json-rsr — %foreign declarations binding into libhpm_json.so.

module HpmJson.ABI.Foreign

import Data.Buffer
import HpmJson.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Parse / free
--------------------------------------------------------------------------------

%foreign "C:hpm_json_parse, libhpm_json"
prim__parse : Buffer -> Int -> PrimIO AnyPtr

||| Parse a JSON byte slice. Returns NULL on malformed input.
export
parse : Buffer -> Int -> IO AnyPtr
parse src len = primIO $ prim__parse src len

%foreign "C:hpm_json_free, libhpm_json"
prim__free : AnyPtr -> PrimIO ()

export
free : AnyPtr -> IO ()
free v = primIO $ prim__free v

--------------------------------------------------------------------------------
-- Type detection
--------------------------------------------------------------------------------

%foreign "C:hpm_json_type, libhpm_json"
prim__type : AnyPtr -> PrimIO Int

export
jsonType : AnyPtr -> IO JsonType
jsonType v = do
  rc <- primIO $ prim__type v
  pure (jsonTypeFromInt rc)

--------------------------------------------------------------------------------
-- Typed extraction
--------------------------------------------------------------------------------

%foreign "C:hpm_json_bool, libhpm_json"
prim__bool : AnyPtr -> PrimIO Int

export
jsonBool : AnyPtr -> IO Int
jsonBool v = primIO $ prim__bool v

%foreign "C:hpm_json_int, libhpm_json"
prim__int : AnyPtr -> PrimIO Int

export
jsonInt : AnyPtr -> IO Int
jsonInt v = primIO $ prim__int v

%foreign "C:hpm_json_float, libhpm_json"
prim__float : AnyPtr -> PrimIO Double

export
jsonFloat : AnyPtr -> IO Double
jsonFloat v = primIO $ prim__float v

%foreign "C:hpm_json_string, libhpm_json"
prim__string : AnyPtr -> Buffer -> Int -> PrimIO Int

export
jsonString : AnyPtr -> Buffer -> Int -> IO StringResult
jsonString v out cap = do
  rc <- primIO $ prim__string v out cap
  pure (stringResultFromInt rc)

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

%foreign "C:hpm_json_object_get, libhpm_json"
prim__objectGet : AnyPtr -> Buffer -> Int -> PrimIO AnyPtr

export
objectGet : AnyPtr -> Buffer -> Int -> IO AnyPtr
objectGet v key keyLen = primIO $ prim__objectGet v key keyLen

%foreign "C:hpm_json_array_len, libhpm_json"
prim__arrayLen : AnyPtr -> PrimIO Int

export
arrayLen : AnyPtr -> IO Int
arrayLen v = primIO $ prim__arrayLen v

%foreign "C:hpm_json_array_get, libhpm_json"
prim__arrayGet : AnyPtr -> Int -> PrimIO AnyPtr

export
arrayGet : AnyPtr -> Int -> IO AnyPtr
arrayGet v idx = primIO $ prim__arrayGet v idx

--------------------------------------------------------------------------------
-- Escaping
--------------------------------------------------------------------------------

%foreign "C:hpm_json_escape_string, libhpm_json"
prim__escape : Buffer -> Int -> Buffer -> Int -> PrimIO Int

||| Escape a UTF-8 string for inclusion in a JSON literal. Does NOT add
||| surrounding quotes (caller does that).
export
escapeString : Buffer -> Int -> Buffer -> Int -> IO StringResult
escapeString src srcLen out cap = do
  rc <- primIO $ prim__escape src srcLen out cap
  pure (stringResultFromInt rc)
