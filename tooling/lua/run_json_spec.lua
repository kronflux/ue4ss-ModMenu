-- These specs check that the runner encodes strings as JSON, because the C# host parses the
-- printed summary as JSON and a Lua-quoted failure message would make that parse fail.

local encode = _RUNNER.encode

assert_eq("encode escapes newline and quote", encode('a\n"b"'), '"a\\n\\"b\\""')
assert_eq("encode escapes backslash", encode("a\\b"), '"a\\\\b"')
assert_eq("encode escapes tab, carriage return, backspace and form feed by name",
    encode("\t\r\b\f"), '"\\t\\r\\b\\f"')
assert_eq("encode escapes other control bytes as unicode", encode("\1"), '"\\u0001"')
assert_eq("encode escapes the unit separator as unicode", encode("\31"), '"\\u001f"')
assert_eq("encode leaves plain text unchanged", encode("plain text"), '"plain text"')
assert_eq("encode writes an object with sorted keys", encode({ x = 1, y = "s" }), '{"x":1,"y":"s"}')
