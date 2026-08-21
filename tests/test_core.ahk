#Requires AutoHotkey v2.0
#Include ..\PDFHeaderTool.ahk

global TestFails := 0, TestCount := 0

AssertEq(got, want, label) {
    global TestFails, TestCount
    TestCount++
    if (got != want) {
        TestFails++
        FileAppend("FAIL " label ": got [" got "] want [" want "]`n", "*")
    }
}
AssertTrue(cond, label) => AssertEq(cond ? 1 : 0, 1, label)

; ---- Json.Parse ----
AssertEq(Json.Parse('"hello"'), "hello", "parse plain string")
AssertEq(Json.Parse('"a\"b\\c\/d"'), 'a"b\c/d', "parse escapes quote backslash slash")
AssertEq(Json.Parse('"line\nbreak"'), "line`nbreak", "parse newline escape")
AssertEq(Json.Parse('"\u0041\u00e9"'), "A" Chr(0xE9), "parse unicode escapes")
AssertEq(Json.Parse("42"), 42, "parse int")
AssertEq(Json.Parse("-3.5"), -3.5, "parse float")
AssertEq(Json.Parse("true"), true, "parse true")
AssertEq(Json.Parse("null"), "", "null becomes empty string")
m := Json.Parse('{"a": 1, "b": {"c": [1, 2, "x"]}, "d": null}')
AssertEq(m["a"], 1, "object int field")
AssertEq(m["b"]["c"][3], "x", "nested array string")
AssertEq(m["d"], "", "object null field")
AssertEq(m.Count, 3, "object key count")
inner := Json.Parse('{"text": "{\"date\":\"03\/14\/2023\"}"}')
AssertEq(Json.Parse(inner["text"])["date"], "03/14/2023", "JSON nested inside a JSON string")
threw := 0
try
    Json.Parse('{"a": 1')
catch
    threw := 1
AssertEq(threw, 1, "truncated JSON throws")

; ---- Json.Escape ----
AssertEq(Json.Escape('say "hi"'), 'say \"hi\"', "escape quotes")
AssertEq(Json.Escape("back\slash"), "back\\slash", "escape backslash")
AssertEq(Json.Escape("tab`there"), "tab\there", "escape tab")
AssertEq(Json.Parse('"' Json.Escape("round`ntrip " Chr(0x2014) ' "q"') '"'),
    "round`ntrip " Chr(0x2014) ' "q"', "escape/parse round trip")

FileAppend((TestFails ? "FAILED " TestFails "/" TestCount : "PASSED " TestCount) " tests`n", "*")
ExitApp(TestFails)
