#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
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
AssertEq(h.text, "MM/DD/YYYY" sep "John Smith, MD", "blank date placeholder, blank note type omitted")
AssertEq(h.marks.Length, 0, "no marks with blank date and blank note type")
h := BuildHeader("bad date", "", "MRI")
AssertEq(h.text, "MM/DD/YYYY" sep "MRI", "unparseable date placeholder, blank provider omitted")
AssertEq(h.marks.Length, 0, "no marks with bad date and blank provider")
h := BuildHeader("2023-03-14", "", "")
AssertEq(h.text, "03/14/2023", "date alone when provider and note type both blank")
AssertEq(h.marks.Length, 0, "no marks with only date present")

; ---- BuildRequestBody ----
body := BuildRequestBody("QUJD", "claude-opus-5")
req := Json.Parse(body)
AssertEq(req["model"], "claude-opus-5", "req model")
AssertEq(req["max_tokens"], 16000, "req max_tokens")
AssertEq(req["fallbacks"], "default", "req fallbacks")
AssertEq(req["messages"][1]["content"][1]["type"], "document", "req document block first")
AssertEq(req["messages"][1]["content"][1]["source"]["media_type"], "application/pdf", "req pdf media type")
AssertEq(req["messages"][1]["content"][1]["source"]["data"], "QUJD", "req b64 passthrough")
AssertEq(req["messages"][1]["content"][2]["type"], "text", "req text block second")
AssertTrue(InStr(req["messages"][1]["content"][2]["text"], "date_of_service") > 0, "req prompt mentions field")
fmt := req["output_config"]["format"]
AssertEq(fmt["type"], "json_schema", "req schema type")
AssertEq(fmt["schema"]["additionalProperties"], false, "req schema closed")
AssertEq(fmt["schema"]["required"].Length, 4, "req schema requires 4 fields")

; ---- ExtractFields ----
ok := '{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},'
    . '{"type":"text","text":"{\"date_of_service\":\"2023-03-14\",\"provider_name\":\"John Smith, MD\",\"note_type\":null}"}]}'
f := ExtractFields(ok)
AssertEq(f.ok ? 1 : 0, 1, "extract ok")
AssertEq(f.date, "2023-03-14", "extract date")
AssertEq(f.provider, "John Smith, MD", "extract provider")
AssertEq(f.notetype, "", "extract null note type as empty")
f := ExtractFields('{"stop_reason":"refusal","content":[]}')
AssertEq(f.ok ? 1 : 0, 0, "refusal not ok")
f := ExtractFields('{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}')
AssertEq(f.ok ? 1 : 0, 0, "api error not ok")
AssertTrue(InStr(f.err, "invalid x-api-key") > 0, "api error message surfaced")
f := ExtractFields('{"stop_reason":"max_tokens","content":[{"type":"text","text":"{\"date_of"}]}')
AssertEq(f.ok ? 1 : 0, 0, "max_tokens not ok")

; ---- FileToBase64 ----
b64path := A_Temp "\pdfheadertool_b64test.bin"
try FileDelete(b64path)
bf := FileOpen(b64path, "w", "UTF-8-RAW")  ; RAW: no BOM, or the vector breaks
bf.Write("Man")
bf.Close()
AssertEq(FileToBase64(b64path), "TWFu", "base64 known vector")
FileDelete(b64path)

; ---- LoadSettings ----
sPath := A_Temp "\pdfheadertool_settings_test.ini"
try FileDelete(sPath)
cfg := LoadSettings(sPath)
AssertEq(cfg.firstRun ? 1 : 0, 1, "settings first run")
AssertEq(cfg.hotkey, "F8", "settings default hotkey")
AssertEq(cfg.model, "claude-opus-5", "settings default model")
AssertEq(cfg.apiKey, "", "settings default key empty")
AssertEq(cfg.showButton ? 1 : 0, 1, "settings default button on")
AssertTrue(FileExist(sPath) != "", "settings file created")
IniWrite("sk-test-123", sPath, "Settings", "ApiKey")
IniWrite("", sPath, "Settings", "Hotkey")
IniWrite("0", sPath, "Settings", "ShowButton")
cfg := LoadSettings(sPath)
AssertEq(cfg.firstRun ? 1 : 0, 0, "settings second run")
AssertEq(cfg.apiKey, "sk-test-123", "settings reads key")
AssertEq(cfg.hotkey, "", "settings blank hotkey allowed")
AssertEq(cfg.showButton ? 1 : 0, 0, "settings button off")
FileDelete(sPath)

; ---- BuildRequestBody model-gated fallbacks (Task 6b) ----
reqCheap := Json.Parse(BuildRequestBody("QUJD", "claude-haiku-4-5"))
AssertEq(reqCheap.Has("fallbacks") ? 1 : 0, 0, "no fallbacks key for cheap model")
AssertEq(reqCheap["model"], "claude-haiku-4-5", "cheap model passthrough")
AssertEq(reqCheap["max_tokens"], 16000, "cheap model keeps max_tokens")
reqSonnet := Json.Parse(BuildRequestBody("QUJD", "claude-sonnet-5"))
AssertEq(reqSonnet.Has("fallbacks") ? 1 : 0, 0, "no fallbacks key for sonnet")
reqOpus := Json.Parse(BuildRequestBody("QUJD", "claude-opus-5"))
AssertEq(reqOpus["fallbacks"], "default", "opus keeps fallbacks default")

; ---- Task 9: header font settings ----
sPath9 := A_Temp "\pdfheadertool_settings_t9.ini"
try FileDelete(sPath9)
cfg9 := LoadSettings(sPath9)
AssertEq(cfg9.headerFont, "Times New Roman", "font default name")
AssertEq(cfg9.headerSize, 20, "font default size")
IniWrite("Georgia", sPath9, "Settings", "HeaderFont")
IniWrite("26", sPath9, "Settings", "HeaderSize")
cfg9 := LoadSettings(sPath9)
AssertEq(cfg9.headerFont, "Georgia", "font reads name")
AssertEq(cfg9.headerSize, 26, "font reads size")
IniWrite("huge", sPath9, "Settings", "HeaderSize")
cfg9 := LoadSettings(sPath9)
AssertEq(cfg9.headerSize, 20, "font size garbage falls back")
IniWrite("200", sPath9, "Settings", "HeaderSize")
cfg9 := LoadSettings(sPath9)
AssertEq(cfg9.headerSize, 20, "font size out of range falls back")
FileDelete(sPath9)
AssertEq(HDR_ValidSize(14), 14, "validsize passthrough")
AssertEq(HDR_ValidSize(""), 20, "validsize empty")

; ---- Task 11: model options ----
mo := ModelOptions()
AssertEq(mo.Length, 3, "model options count")
AssertEq(mo[1].id, "claude-opus-5", "model options first id")
AssertTrue(InStr(ModelNoteFor("claude-haiku-4-5"), "cheapest") > 0, "haiku note text")
AssertEq(ModelNoteFor("claude-nonexistent"), "", "unknown model empty note")

; ---- Task 12: imaging headers + schema field ----
sep12 := " " Chr(0x2014) " "
h12 := BuildHeader("2023-03-14", "Rad Guy, MD", "MRI Lumbar Spine", false)
AssertEq(h12.text, "03/14/2023" sep12 "MRI Lumbar Spine", "imaging header omits provider")
AssertEq(h12.marks.Length, 0, "imaging full has no marks")
h12 := BuildHeader("", "", "", false)
AssertEq(h12.text, "MM/DD/YYYY", "imaging blank date placeholder, blank note type omitted")
AssertEq(h12.marks.Length, 0, "no marks with imaging blank date and blank note type")
h12 := BuildHeader("2023-03-14", "John Smith, MD", "Office Visit")
AssertEq(h12.text, "03/14/2023" sep12 "John Smith, MD" sep12 "Office Visit", "default still three-part")
f12 := ExtractFields('{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"date_of_service\":\"2023-03-14\",\"provider_name\":\"R, MD\",\"note_type\":\"MRI\",\"is_imaging\":true}"}]}')
AssertEq(f12.imaging ? 1 : 0, 1, "extract imaging true")
f12 := ExtractFields('{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"date_of_service\":null,\"provider_name\":null,\"note_type\":null}"}]}')
AssertEq(f12.imaging ? 1 : 0, 0, "extract imaging default false")
req12 := Json.Parse(BuildRequestBody("QUJD", "claude-opus-5"))
AssertTrue(InStr(req12["messages"][1]["content"][2]["text"], "is_imaging") > 0, "prompt mentions is_imaging")

FileAppend((TestFails ? "FAILED " TestFails "/" TestCount : "PASSED " TestCount) " tests`n", "*")
ExitApp(TestFails)
