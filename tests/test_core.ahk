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

; ---- NormalizeDateMDY ----
AssertEq(NormalizeDateMDY("2023-03-14"), "03/14/2023", "date ISO")
AssertEq(NormalizeDateMDY("3/4/2023"), "03/04/2023", "date short mdy")
AssertEq(NormalizeDateMDY("03-14-2023"), "03/14/2023", "date dashes")
AssertEq(NormalizeDateMDY("3/4/24"), "03/04/2024", "date 2-digit year windows forward")
AssertEq(NormalizeDateMDY("3/4/97"), "03/04/1997", "date 2-digit year windows back")
AssertEq(NormalizeDateMDY("March 14, 2023"), "03/14/2023", "date month name")
AssertEq(NormalizeDateMDY("Sept 3 2021"), "09/03/2021", "date month abbrev no comma")
AssertEq(NormalizeDateMDY("June 7, 24"), "06/07/2024", "date month name 2-digit year")
AssertEq(NormalizeDateMDY(" 03/14/2023 "), "03/14/2023", "date trims")
AssertEq(NormalizeDateMDY("14/33/2023"), "", "date impossible rejected")
AssertEq(NormalizeDateMDY("last Tuesday"), "", "date garbage rejected")
AssertEq(NormalizeDateMDY(""), "", "date empty")

; ---- BuildHeader ----
sep := " " Chr(0x2014) " "
h := BuildHeader("2023-03-14", "John Smith, MD", "Office Visit")
AssertEq(h.text, "03/14/2023" sep "John Smith, MD" sep "Office Visit", "header full")
AssertEq(h.marks.Length, 0, "header full has no marks")
h := BuildHeader("", "John Smith, MD", "")
AssertEq(h.text, "MM/DD/YYYY" sep "John Smith, MD" sep "NOTE TYPE", "header placeholders")
AssertEq(h.marks.Length, 2, "two placeholder marks")
AssertEq(h.marks[1].start, 1, "date mark start")
AssertEq(h.marks[1].len, 10, "date mark len")
AssertEq(SubStr(h.text, h.marks[2].start, h.marks[2].len), "NOTE TYPE", "note mark covers placeholder")
h := BuildHeader("bad date", "", "MRI")
AssertEq(SubStr(h.text, h.marks[1].start, h.marks[1].len), "MM/DD/YYYY", "unparseable date becomes placeholder")
AssertEq(SubStr(h.text, h.marks[2].start, h.marks[2].len), "PROVIDER", "empty provider becomes placeholder")

FileAppend((TestFails ? "FAILED " TestFails "/" TestCount : "PASSED " TestCount) " tests`n", "*")
ExitApp(TestFails)
