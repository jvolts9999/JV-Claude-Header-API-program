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

; ---- Task 14: style toggle, bold, lines-below settings ----
sPath14 := A_Temp "\pdfheadertool_settings_t14.ini"
try FileDelete(sPath14)
cfg14 := LoadSettings(sPath14)
AssertEq(cfg14.applyStyle ? 1 : 0, 1, "style default on")
AssertEq(cfg14.headerBold ? 1 : 0, 0, "bold default off")
AssertEq(cfg14.linesBelow, 2, "lines below default 2")
IniWrite("0", sPath14, "Settings", "LinesBelow")
cfg14 := LoadSettings(sPath14)
AssertEq(cfg14.linesBelow, 0, "lines below 0 stays 0")
IniWrite("7", sPath14, "Settings", "LinesBelow")
cfg14 := LoadSettings(sPath14)
AssertEq(cfg14.linesBelow, 2, "lines below out of range falls back")
IniWrite("abc", sPath14, "Settings", "LinesBelow")
cfg14 := LoadSettings(sPath14)
AssertEq(cfg14.linesBelow, 2, "lines below garbage falls back")
FileDelete(sPath14)
AssertEq(HDR_ValidLines(3), 3, "validlines passthrough")
AssertEq(HDR_ValidLines(""), 2, "validlines empty")

; ---- Task 16: Summarize selection ----

; LoadSettings showSummarize
sPath16 := A_Temp "\pdfheadertool_settings_t16.ini"
try FileDelete(sPath16)
cfg16 := LoadSettings(sPath16)
AssertEq(cfg16.showSummarize ? 1 : 0, 1, "settings default show summarize on")
IniWrite("0", sPath16, "Settings", "ShowSummarize")
cfg16 := LoadSettings(sPath16)
AssertEq(cfg16.showSummarize ? 1 : 0, 0, "settings show summarize off override")
FileDelete(sPath16)

; ModelWantsFallbacks
AssertEq(ModelWantsFallbacks("claude-opus-5") ? 1 : 0, 1, "modelwantsfallbacks true for opus")
AssertEq(ModelWantsFallbacks("claude-haiku-4-5") ? 1 : 0, 0, "modelwantsfallbacks false for haiku")

; BuildSummaryRequestBody
excerpt16 := "Patient reports ongoing low back pain radiating to the left leg."
sReq := Json.Parse(BuildSummaryRequestBody(excerpt16, "claude-opus-5"))
AssertEq(sReq["model"], "claude-opus-5", "summary req model passthrough")
AssertEq(sReq["max_tokens"], 16000, "summary req max_tokens")
AssertEq(sReq.Has("fallbacks") ? 1 : 0, 1, "summary req fallbacks present for opus")
sReqCheap := Json.Parse(BuildSummaryRequestBody(excerpt16, "claude-haiku-4-5"))
AssertEq(sReqCheap.Has("fallbacks") ? 1 : 0, 0, "summary req fallbacks absent for haiku")
promptTxt := sReq["messages"][1]["content"][1]["text"]
AssertTrue(InStr(promptTxt, "2-4 sentences") > 0 && InStr(promptTxt, excerpt16) > 0,
    "summary prompt has guidance and excerpt")
AssertEq(sReq.Has("output_config") ? 1 : 0, 0, "summary req has no output_config")

; ExtractText
tOk := '{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},'
    . '{"type":"text","text":"Patient was seen for back pain. MRI showed a disc bulge. Plan is physical therapy."}]}'
tf := ExtractText(tOk)
AssertEq(tf.text, "Patient was seen for back pain. MRI showed a disc bulge. Plan is physical therapy.",
    "extracttext happy path with leading thinking block")
tf := ExtractText('{"stop_reason":"refusal","content":[]}')
AssertEq(tf.ok ? 1 : 0, 0, "extracttext refusal not ok")
tf := ExtractText('{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}')
AssertEq(tf.ok ? 1 : 0, 0, "extracttext api error not ok")
tf := ExtractText('{"stop_reason":"end_turn","content":[{"type":"text","text":"   "}]}')
AssertEq(tf.err, "The model returned no text.", "extracttext empty content after trim")

; ---- Task 16 addendum: page-fallback summary ----
pReq := Json.Parse(BuildPageSummaryRequestBody("QUJD", "claude-opus-5"))
AssertEq(pReq["model"], "claude-opus-5", "page summary req model")
AssertEq(pReq["max_tokens"], 16000, "page summary req max_tokens")
AssertEq(pReq["messages"][1]["content"][1]["type"], "document", "page summary req document block first")
AssertEq(pReq["messages"][1]["content"][1]["source"]["media_type"], "application/pdf", "page summary req pdf media type")
AssertEq(pReq["messages"][1]["content"][1]["source"]["data"], "QUJD", "page summary req b64 passthrough")
AssertEq(pReq["messages"][1]["content"][2]["type"], "text", "page summary req text block second")
AssertTrue(InStr(pReq["messages"][1]["content"][2]["text"], "2-4 sentences") > 0, "page summary req prompt mentions guidance")
AssertEq(pReq.Has("output_config") ? 1 : 0, 0, "page summary req has no output_config")
AssertEq(pReq["fallbacks"], "default", "page summary req fallbacks present for opus")
pReqCheap := Json.Parse(BuildPageSummaryRequestBody("QUJD", "claude-haiku-4-5"))
AssertEq(pReqCheap.Has("fallbacks") ? 1 : 0, 0, "page summary req fallbacks absent for haiku")

; ---- Task 17: summary font, page queue, summarize hotkey ----

; HDR_ValidSize fallback param
AssertEq(HDR_ValidSize(""), 20, "validsize fallback param default still 20")
AssertEq(HDR_ValidSize("", 12), 12, "validsize fallback param explicit 12")

; LoadSettings: summaryFont / summarySize / summarizeHotkey
sPath17 := A_Temp "\pdfheadertool_settings_t17.ini"
try FileDelete(sPath17)
cfg17 := LoadSettings(sPath17)
AssertEq(cfg17.summaryFont, "Times New Roman", "summary font default name")
AssertEq(cfg17.summarySize, 12, "summary font default size")
AssertEq(cfg17.summarizeHotkey, "", "summarize hotkey default empty")
IniWrite("abc", sPath17, "Settings", "SummarySize")
cfg17 := LoadSettings(sPath17)
AssertEq(cfg17.summarySize, 12, "summary font size garbage falls back to 12")
IniWrite("F9", sPath17, "Settings", "SummarizeHotkey")
cfg17 := LoadSettings(sPath17)
AssertEq(cfg17.summarizeHotkey, "F9", "summarize hotkey override read")
FileDelete(sPath17)

; BuildQueueSummaryRequestBody
qList := ["QUJD", "REVG", "R0hJ"]
qReq := Json.Parse(BuildQueueSummaryRequestBody(qList, "claude-opus-5"))
AssertEq(qReq["messages"][1]["content"].Length, 4, "queue summary req 4 content blocks")
AssertEq(qReq["messages"][1]["content"][1]["type"], "document", "queue summary req first block is document")
AssertEq(qReq["messages"][1]["content"][1]["source"]["data"], "QUJD", "queue summary req first doc b64 passthrough")
AssertEq(qReq["messages"][1]["content"][2]["source"]["data"], "REVG", "queue summary req second doc b64 passthrough")
AssertEq(qReq["messages"][1]["content"][3]["source"]["data"], "R0hJ", "queue summary req third doc b64 passthrough")
qPromptTxt := qReq["messages"][1]["content"][4]["text"]
AssertTrue(InStr(qPromptTxt, "one multi-page note") > 0 && InStr(qPromptTxt, "2-4 sentences") > 0,
    "queue summary req prompt mentions multi-page and guidance")
AssertEq(qReq.Has("output_config") ? 1 : 0, 0, "queue summary req has no output_config")
AssertEq(qReq["fallbacks"], "default", "queue summary req fallbacks present for opus")
qReqCheap := Json.Parse(BuildQueueSummaryRequestBody(qList, "claude-haiku-4-5"))
AssertEq(qReqCheap.Has("fallbacks") ? 1 : 0, 0, "queue summary req fallbacks absent for haiku")

; ---- Task 18: queue hotkey, beep, usage/cost tracking ----

; LoadSettings: queueHotkey / beep
sPath18 := A_Temp "\pdfheadertool_settings_t18.ini"
try FileDelete(sPath18)
cfg18 := LoadSettings(sPath18)
AssertEq(cfg18.queueHotkey, "", "queue hotkey default empty")
AssertEq(cfg18.beep ? 1 : 0, 1, "beep default on")
IniWrite("F10", sPath18, "Settings", "QueueHotkey")
IniWrite("0", sPath18, "Settings", "Beep")
cfg18 := LoadSettings(sPath18)
AssertEq(cfg18.queueHotkey, "F10", "queue hotkey override read")
AssertEq(cfg18.beep ? 1 : 0, 0, "beep override off")
FileDelete(sPath18)

; ExtractUsage
uOk := '{"stop_reason":"end_turn","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":1234,"output_tokens":56}}'
u := ExtractUsage(uOk)
AssertEq(u.inTok, 1234, "extractusage input tokens")
AssertEq(u.outTok, 56, "extractusage output tokens")
uMissing := '{"stop_reason":"end_turn","content":[{"type":"text","text":"hi"}]}'
u2 := ExtractUsage(uMissing)
AssertEq(u2.inTok, 0, "extractusage missing usage input zero")
AssertEq(u2.outTok, 0, "extractusage missing usage output zero")

; EstimateCents
AssertEq(EstimateCents("claude-opus-5", 1000, 1000), 3.0, "estimatecents opus math")
AssertEq(EstimateCents("claude-sonnet-5", 1000, 1000), 1.8, "estimatecents sonnet math")
AssertEq(EstimateCents("claude-haiku-4-5", 1000, 1000), 0.6, "estimatecents haiku math")
AssertEq(EstimateCents("claude-nonexistent", 1000, 1000), -1, "estimatecents unknown model")

; ---- Task 19: blank-line font fix, two-tone chime, summary detail levels ----

; HDR_DetailClause
AssertEq(HDR_DetailClause("concise"), "Write 1-2 sentences of plain prose.",
    "detail clause concise")
AssertEq(HDR_DetailClause("standard"), "Write 2-4 sentences of plain prose covering what happened, the key findings, and the plan.",
    "detail clause standard")
AssertEq(HDR_DetailClause("detailed"), "Write 4-8 sentences of plain prose covering what happened, the relevant history, the key findings, and the plan.",
    "detail clause detailed")
AssertEq(HDR_DetailClause("garbage"), "Write 2-4 sentences of plain prose covering what happened, the key findings, and the plan.",
    "detail clause garbage falls back to standard")

; LoadSettings: summaryDetail
sPath19 := A_Temp "\pdfheadertool_settings_t19.ini"
try FileDelete(sPath19)
cfg19 := LoadSettings(sPath19)
AssertEq(cfg19.summaryDetail, "standard", "summary detail default standard")
IniWrite("Detailed", sPath19, "Settings", "SummaryDetail")
cfg19 := LoadSettings(sPath19)
AssertEq(cfg19.summaryDetail, "detailed", "summary detail override read, case-insensitive")
IniWrite("garbage", sPath19, "Settings", "SummaryDetail")
cfg19 := LoadSettings(sPath19)
AssertEq(cfg19.summaryDetail, "standard", "summary detail garbage clamp falls back to standard")
FileDelete(sPath19)

; The three summary builders honor detail:="concise" (default "2-4 sentences"
; behavior is already covered by the unmodified Task 16/17 assertions above).
sReqConcise := Json.Parse(BuildSummaryRequestBody(excerpt16, "claude-opus-5", "concise"))
AssertTrue(InStr(sReqConcise["messages"][1]["content"][1]["text"], "1-2 sentences") > 0,
    "summary req concise detail shortens prompt")
pReqConcise := Json.Parse(BuildPageSummaryRequestBody("QUJD", "claude-opus-5", "concise"))
AssertTrue(InStr(pReqConcise["messages"][1]["content"][2]["text"], "1-2 sentences") > 0,
    "page summary req concise detail shortens prompt")
qReqConcise := Json.Parse(BuildQueueSummaryRequestBody(qList, "claude-opus-5", "concise"))
AssertTrue(InStr(qReqConcise["messages"][1]["content"][4]["text"], "1-2 sentences") > 0,
    "queue summary req concise detail shortens prompt")

; ---- Task 20: one-press header + summary combo ----

; LoadSettings: comboInsert
sPath20 := A_Temp "\pdfheadertool_settings_t20.ini"
try FileDelete(sPath20)
cfg20 := LoadSettings(sPath20)
AssertEq(cfg20.comboInsert ? 1 : 0, 1, "combo insert default on")
IniWrite("0", sPath20, "Settings", "ComboInsert")
cfg20 := LoadSettings(sPath20)
AssertEq(cfg20.comboInsert ? 1 : 0, 0, "combo insert override off")
FileDelete(sPath20)

; ---- Task 22: SOAP summary format, med-legal orientation, custom instructions ----

; HDR_ValidFormat
AssertEq(HDR_ValidFormat("soap"), "soap", "validformat soap passthrough")
AssertEq(HDR_ValidFormat("prose"), "prose", "validformat prose")
AssertEq(HDR_ValidFormat("garbage"), "soap", "validformat garbage falls back to soap")

; LoadSettings: summaryFormat / customInstructions
sPath22 := A_Temp "\pdfheadertool_settings_t22.ini"
try FileDelete(sPath22)
cfg22 := LoadSettings(sPath22)
AssertEq(cfg22.summaryFormat, "soap", "summary format default soap")
AssertEq(cfg22.customInstructions, "", "custom instructions default empty")
IniWrite("Prose", sPath22, "Settings", "SummaryFormat")
IniWrite("note all med changes", sPath22, "Settings", "CustomInstructions")
cfg22 := LoadSettings(sPath22)
AssertEq(cfg22.summaryFormat, "prose", "summary format override read, case-insensitive")
AssertEq(cfg22.customInstructions, "note all med changes", "custom instructions override roundtrip")
FileDelete(sPath22)

; HDR_FormatClause: prose mode is byte-identical to HDR_DetailClause
AssertEq(HDR_FormatClause("prose", "standard"), HDR_DetailClause("standard"),
    "format clause prose mode matches detail clause exactly")

; Builders: default format is soap - labeled lines plus med-legal framing,
; same sentence budget as before
sReq22 := Json.Parse(BuildSummaryRequestBody(excerpt16, "claude-opus-5"))
defaultTxt22 := sReq22["messages"][1]["content"][1]["text"]
AssertTrue(InStr(defaultTxt22, "Subjective:") > 0, "default summary format is soap - has Subjective label")
AssertTrue(InStr(defaultTxt22, "2-4 sentences") > 0, "default summary detail still standard - 2-4 sentences")

; format:="prose" restores the old shape exactly (no section labels, same
; sentence budget, same no-headings phrase)
sReqProse22 := Json.Parse(BuildSummaryRequestBody(excerpt16, "claude-opus-5", "standard", "prose"))
proseTxt22 := sReqProse22["messages"][1]["content"][1]["text"]
AssertTrue(InStr(proseTxt22, "Subjective:") = 0 && InStr(proseTxt22, "2-4 sentences") > 0
    && InStr(proseTxt22, "No preamble, no headings, no bullet points") > 0,
    "format=prose lacks Subjective label and matches old prose shape")

; Custom instructions must land AFTER the excerpt content, not between the
; "Excerpt:" label and the excerpt itself - the label must directly precede
; what it introduces.
sReqOrder22 := Json.Parse(BuildSummaryRequestBody("MY-EXCERPT-TEXT", "claude-opus-5", "standard", "soap", "note med changes"))
orderTxt22 := sReqOrder22["messages"][1]["content"][1]["text"]
AssertTrue(InStr(orderTxt22, "MY-EXCERPT-TEXT") > 0, "excerpt text present in summary prompt")
AssertTrue(InStr(orderTxt22, "Additional instructions:") > InStr(orderTxt22, "MY-EXCERPT-TEXT"),
    "custom instructions come after the excerpt, not before it")
AssertTrue(InStr(orderTxt22, "Excerpt:") < InStr(orderTxt22, "MY-EXCERPT-TEXT"),
    "Excerpt label directly precedes the excerpt content")

; Custom summary instructions: appended when present, absent when empty
sReqCustom22 := Json.Parse(BuildSummaryRequestBody(excerpt16, "claude-opus-5", "standard", "soap", "note all med changes"))
customTxt22 := sReqCustom22["messages"][1]["content"][1]["text"]
AssertTrue(InStr(customTxt22, "Additional instructions: note all med changes") > 0,
    "custom instructions appear in summary prompt when present")
AssertEq(InStr(defaultTxt22, "Additional instructions:"), 0, "custom instructions absent when empty")

qReqCustom22 := Json.Parse(BuildQueueSummaryRequestBody(qList, "claude-opus-5", "standard", "soap", "note all med changes"))
qCustomTxt22 := qReqCustom22["messages"][1]["content"][4]["text"]
AssertTrue(InStr(qCustomTxt22, "Additional instructions: note all med changes") > 0,
    "custom instructions appear in queue summary prompt when present")

FileAppend((TestFails ? "FAILED " TestFails "/" TestCount : "PASSED " TestCount) " tests`n", "*")
ExitApp(TestFails)
