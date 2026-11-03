local Json = require("ModMenu.store.json")

assert_true("IsSafe string", Json.IsSafe("dock") == true)
assert_true("IsSafe number", Json.IsSafe(3) == true)
assert_true("IsSafe object", Json.IsSafe({ dock = "left", n = 2 }) == true)
assert_true("IsSafe rejects function", Json.IsSafe(function() end) == false)
assert_true("IsSafe rejects nan", Json.IsSafe(0 / 0) == false)

local text = Json.Encode({ dock = "right", n = 2 }, 0)
assert_true("Encode writes object", type(text) == "string" and text:sub(1, 1) == "{")
assert_true("Encode has dock", text:find('"dock"', 1, true) ~= nil)
assert_true("Encode has right", text:find('"right"', 1, true) ~= nil)

local obj = Json.DecodeObject(text)
assert_eq("Decode dock", obj.dock, "right")
assert_eq("Decode number", obj.n, 2)

local ok, err = pcall(Json.DecodeObject, "[1,2]")
assert_true("Decode root must be object", ok == false)
assert_true("Decode error mentions object", type(err) == "string" and err:find("object", 1, true) ~= nil)

-- A null inside an array must keep its place, so that the array keeps its length and the
-- elements after it keep their indexes.
local arr = Json.Decode("[1,null,3]")
assert_eq("null round trip length", #arr, 3)
assert_true("null round trip element 2 is the sentinel", arr[2] == Json.null)
assert_eq("null round trip element 3", arr[3], 3)
-- The encoder writes arrays across lines, so the round trip is compared with the encoder's
-- own output for the same three values as well as with that exact text.
assert_eq("null round trip encode", Json.Encode(arr, 0), Json.Encode({ 1, Json.null, 3 }, 0))
assert_eq("null round trip encode text", Json.Encode(arr, 0), "[\n  1,\n  null,\n  3\n]")
assert_true("decode top-level null", Json.Decode("null") == Json.null)
assert_eq("encode null sentinel", Json.Encode(Json.null, 0), "null")
assert_eq("null sentinel tostring", tostring(Json.null), "null")

-- Every decode shares the one sentinel, so a write into it must fail rather than change the
-- null that every later decode returns.
local okWrite, writeErr = pcall(function()
    Json.null.x = 1
end)
assert_true("null sentinel rejects a write", okWrite == false)
assert_true("null sentinel write error names it read-only",
    type(writeErr) == "string" and writeErr:find("json.null is read-only", 1, true) ~= nil)
assert_true("null sentinel stays empty after a write", rawget(Json.null, "x") == nil)
assert_eq("null sentinel still encodes as null", Json.Encode(Json.null, 0), "null")

-- An object member that is null is left out, because the store treats a missing key as
-- "use the default" and the sentinel would replace the default.
local withNull = Json.DecodeObject('{"a":null,"b":1}')
assert_true("object null member is absent", withNull.a == nil)
assert_eq("object other member kept", withNull.b, 1)

local okNull = pcall(Json.DecodeObject, "null")
assert_true("DecodeObject rejects a null root", okNull == false)
