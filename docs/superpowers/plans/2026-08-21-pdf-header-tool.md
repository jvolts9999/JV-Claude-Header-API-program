# PDF Header Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single standalone AutoHotkey v2 script: press F8 (or click a floating button) while viewing a medical-record page in Acrobat Pro, and a `MM/DD/YYYY — Provider — Note Type` Heading 1 lands at the Word cursor, with unreadable fields yellow-highlighted.

**Architecture:** One script file (`PDFHeaderTool.ahk`) whose top-level startup is guarded so tests can `#Include` it without launching the GUI. Pure logic (JSON, dates, header text, request bodies, response parsing) is unit-tested headless; COM layers (Acrobat, Word) and the live API call are verified in staged manual checkpoints with John, per the spec's testing plan.

**Tech Stack:** AutoHotkey v2 (`C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`), Acrobat Pro IAC/COM (`AcroExch.*`), Word COM, `WinHttp.WinHttpRequest.5.1`, Claude API (`claude-opus-5`, structured outputs). Tests run via a PowerShell 5.1 harness.

**Spec:** `docs/superpowers/specs/2026-08-21-pdf-header-tool-design.md`

## Global Constraints

- AutoHotkey v2 syntax only. Interpreter: `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`.
- Repo source files are ASCII-only. The em-dash separator is built at runtime as `" " Chr(0x2014) " "` — never a literal em dash in source.
- `PDFHeaderTool.ahk` is the ONLY runtime file. Tests `#Include` it; nothing else is ever `#Include`d by it.
- Top-level executable code in `PDFHeaderTool.ahk` is limited to `#Requires`/`#SingleInstance`, global constant assignments, and the guarded `Main()` call: `if (A_LineFile = A_ScriptFullPath) Main()`. Hotkeys are registered with the `Hotkey()` function inside `Main()`, never with `F8::` label syntax (label syntax would fire when tests include the file).
- API key lives in `%APPDATA%\PDFHeaderTool\settings.ini`, never in the repo, never echoed to any log, message box, or commit.
- Model string: `claude-opus-5` (settings-overridable). Endpoint `https://api.anthropic.com/v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, `anthropic-beta: server-side-fallback-2026-07-01`, body includes `"fallbacks":"default"` and `"max_tokens":16000`. No `thinking` parameter (Opus 5 defaults to adaptive).
- PowerShell steps are Windows PowerShell 5.1: no `&&`, no ternary. AutoHotkey is GUI-subsystem, so the test harness must use `Start-Process -Wait` with redirected output to capture results.
- Word style is assigned numerically (`-2` = `wdStyleHeading1`), highlight numerically (`7` = `wdYellow`).
- Commit after every task with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Scaffold, test harness, JSON parser

**Files:**
- Create: `PDFHeaderTool.ahk`
- Create: `tests\test_core.ahk`
- Create: `tests\run-tests.ps1`
- Create: `.gitignore`

**Interfaces:**
- Produces: `class Json` with `Json.Parse(s)` → Map/Array/String/Number/Boolean (JSON `null` → `""` by design — this tool treats null and empty identically) and `Json.Escape(s)` → JSON-safe string body (no surrounding quotes). Also the include-guard idiom and test helpers `AssertEq(got, want, label)` / `AssertTrue(cond, label)` used by every later task.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
*.out
*.err
Thumbs.db
```

- [ ] **Step 2: Write the skeleton `PDFHeaderTool.ahk`**

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force

; ======================================================================
; PDF Header Tool - standalone. One keypress in Acrobat -> chronology
; header at the Word cursor. Spec: docs\superpowers\specs\
; 2026-08-21-pdf-header-tool-design.md
; ======================================================================

; --- JSON --------------------------------------------------------------
; Minimal strict JSON parser. null parses to "" ON PURPOSE: every field
; this tool reads treats null and empty as the same thing (placeholder).
class Json {
    static Parse(s) {
        pos := 1
        v := Json._Value(s, &pos)
        Json._Ws(s, &pos)
        if (pos <= StrLen(s))
            throw Error("JSON: trailing data at " pos)
        return v
    }
    static _Ws(s, &pos) {
        while (pos <= StrLen(s)) {
            c := SubStr(s, pos, 1)
            if (c != " " && c != "`t" && c != "`n" && c != "`r")
                break
            pos++
        }
    }
    static _Value(s, &pos) {
        Json._Ws(s, &pos)
        c := SubStr(s, pos, 1)
        if (c = "{")
            return Json._Obj(s, &pos)
        if (c = "[")
            return Json._Arr(s, &pos)
        if (c = '"')
            return Json._Str(s, &pos)
        return Json._Lit(s, &pos)
    }
    static _Obj(s, &pos) {
        m := Map()
        pos++
        Json._Ws(s, &pos)
        if (SubStr(s, pos, 1) = "}") {
            pos++
            return m
        }
        loop {
            Json._Ws(s, &pos)
            if (SubStr(s, pos, 1) != '"')
                throw Error("JSON: expected key at " pos)
            k := Json._Str(s, &pos)
            Json._Ws(s, &pos)
            if (SubStr(s, pos, 1) != ":")
                throw Error("JSON: expected colon at " pos)
            pos++
            m[k] := Json._Value(s, &pos)
            Json._Ws(s, &pos)
            c := SubStr(s, pos, 1)
            pos++
            if (c = "}")
                return m
            if (c != ",")
                throw Error("JSON: expected comma or brace at " pos)
        }
    }
    static _Arr(s, &pos) {
        a := []
        pos++
        Json._Ws(s, &pos)
        if (SubStr(s, pos, 1) = "]") {
            pos++
            return a
        }
        loop {
            a.Push(Json._Value(s, &pos))
            Json._Ws(s, &pos)
            c := SubStr(s, pos, 1)
            pos++
            if (c = "]")
                return a
            if (c != ",")
                throw Error("JSON: expected comma or bracket at " pos)
        }
    }
    static _Str(s, &pos) {
        pos++
        out := ""
        loop {
            c := SubStr(s, pos, 1)
            if (c = "")
                throw Error("JSON: unterminated string")
            if (c = '"') {
                pos++
                return out
            }
            if (c = "\") {
                e := SubStr(s, pos + 1, 1)
                if (e = '"')
                    out .= '"'
                else if (e = "\")
                    out .= "\"
                else if (e = "/")
                    out .= "/"
                else if (e = "b")
                    out .= Chr(8)
                else if (e = "f")
                    out .= Chr(12)
                else if (e = "n")
                    out .= "`n"
                else if (e = "r")
                    out .= "`r"
                else if (e = "t")
                    out .= "`t"
                else if (e = "u") {
                    out .= Chr("0x" SubStr(s, pos + 2, 4))
                    pos += 4
                } else
                    throw Error("JSON: bad escape at " pos)
                pos += 2
            } else {
                out .= c
                pos++
            }
        }
    }
    static _Lit(s, &pos) {
        if (SubStr(s, pos, 4) = "true") {
            pos += 4
            return true
        }
        if (SubStr(s, pos, 5) = "false") {
            pos += 5
            return false
        }
        if (SubStr(s, pos, 4) = "null") {
            pos += 4
            return ""
        }
        if RegExMatch(s, "\G-?\d+(\.\d+)?([eE][+-]?\d+)?", &mm, pos) {
            pos += mm.Len[0]
            return mm[0] + 0
        }
        throw Error("JSON: bad literal at " pos)
    }
    static Escape(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`t", "\t")
        out := ""
        loop parse s {
            out .= (Ord(A_LoopField) < 0x20) ? Format("\u{:04X}", Ord(A_LoopField)) : A_LoopField
        }
        return out
    }
}

; --- Startup (guarded so tests can #Include this file) ----------------
Main() {
    ; Filled in by later tasks.
}

if (A_LineFile = A_ScriptFullPath)
    Main()
```

- [ ] **Step 3: Write the failing tests** — `tests\test_core.ahk`

```ahk
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
```

(Note on the second assertion: in AHK, backslash is a literal character — `'a"b\c/d'` is exactly the seven characters the JSON `"a\"b\\c\/d"` unescapes to.)

- [ ] **Step 4: Write the runner** — `tests\run-tests.ps1`

```powershell
$ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$out = Join-Path $env:TEMP "pdfheadertool_tests.out"
$err = Join-Path $env:TEMP "pdfheadertool_tests.err"
$test = Join-Path $PSScriptRoot "test_core.ahk"
$p = Start-Process -FilePath $ahk -ArgumentList "/ErrorStdOut", "`"$test`"" `
    -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
Get-Content $out -ErrorAction SilentlyContinue
Get-Content $err -ErrorAction SilentlyContinue
exit $p.ExitCode
```

- [ ] **Step 5: Run the tests, verify they pass and the exit code is 0**

Run (PowerShell, from repo root): `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: `PASSED 18 tests` (count = number of assertions above), exit code `0`. If any `FAIL` lines print, fix the parser — not the test — unless the test's expected value is provably wrong.

- [ ] **Step 6: Sanity-check the guard**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1` again and confirm no GUI window or tray icon appeared (Main() is empty AND guarded; nothing should show).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold: guarded entry point, JSON parser, test harness

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Date normalizer and header builder

**Files:**
- Modify: `PDFHeaderTool.ahk` (add functions after the Json class)
- Modify: `tests\test_core.ahk` (append tests before the summary line)

**Interfaces:**
- Consumes: test helpers from Task 1.
- Produces: `NormalizeDateMDY(s)` → `"MM/DD/YYYY"` or `""`; `BuildHeader(dateRaw, provider, noteType)` → object `{text: String, marks: Array of {start, len}}` where `marks` are 1-based character ranges of placeholder segments needing yellow highlight. Separator is built at runtime: `" " Chr(0x2014) " "`.

- [ ] **Step 1: Append failing tests to `tests\test_core.ahk`** (insert BEFORE the `FileAppend` summary/`ExitApp` lines; they stay last in every task)

```ahk
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
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: error output mentioning `NormalizeDateMDY` (call to nonexistent function aborts the script — that counts as the failing state).

- [ ] **Step 3: Implement in `PDFHeaderTool.ahk`** (after the Json class, before `Main`)

```ahk
; --- Dates and header text --------------------------------------------
NormalizeDateMDY(s) {
    s := Trim(s)
    if (s = "")
        return ""
    if RegExMatch(s, "^(\d{4})-(\d{1,2})-(\d{1,2})$", &m)
        return HDR_FmtDate(m[2], m[3], m[1])
    if RegExMatch(s, "^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2}|\d{4})$", &m)
        return HDR_FmtDate(m[1], m[2], HDR_WindowYear(m[3]))
    static months := Map("jan",1,"feb",2,"mar",3,"apr",4,"may",5,"jun",6,
        "jul",7,"aug",8,"sep",9,"oct",10,"nov",11,"dec",12)
    if RegExMatch(s, "i)^([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?\s*,?\s+(\d{2}|\d{4})$", &m) {
        key := SubStr(StrLower(m[1]), 1, 3)
        if months.Has(key)
            return HDR_FmtDate(months[key], m[2], HDR_WindowYear(m[3]))
    }
    return ""
}

HDR_WindowYear(y) {
    y := Integer(y)
    if (y >= 100)
        return y
    return (y <= 49) ? 2000 + y : 1900 + y
}

HDR_FmtDate(mo, d, y) {
    mo := Integer(mo), d := Integer(d), y := Integer(y)
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1900 || y > 2100)
        return ""
    return Format("{:02}/{:02}/{:04}", mo, d, y)
}

BuildHeader(dateRaw, provider, noteType) {
    sep := " " Chr(0x2014) " "
    marks := []
    d := NormalizeDateMDY(dateRaw)
    if (d = "") {
        d := "MM/DD/YYYY"
        marks.Push({start: 1, len: StrLen(d)})
    }
    text := d sep
    p := Trim(provider)
    if (p = "") {
        p := "PROVIDER"
        marks.Push({start: StrLen(text) + 1, len: StrLen(p)})
    }
    text .= p sep
    n := Trim(noteType)
    if (n = "") {
        n := "NOTE TYPE"
        marks.Push({start: StrLen(text) + 1, len: StrLen(n)})
    }
    text .= n
    return {text: text, marks: marks}
}
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: `PASSED` with the new total, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Date normalizer and header builder with placeholder marks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Request body, response parsing, base64

**Files:**
- Modify: `PDFHeaderTool.ahk`
- Modify: `tests\test_core.ahk`

**Interfaces:**
- Consumes: `Json`, `BuildHeader` conventions from Tasks 1–2.
- Produces: `BuildRequestBody(b64pdf, model)` → JSON string; `ExtractFields(responseText)` → `{ok: true, date, provider, notetype}` or `{ok: false, err}` (all strings; nulls arrive as `""`); `FileToBase64(path)` → single-line base64 of the file bytes.

- [ ] **Step 1: Append failing tests**

```ahk
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
AssertEq(fmt["schema"]["required"].Length, 3, "req schema requires 3 fields")

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
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: failure/abort mentioning `BuildRequestBody`.

- [ ] **Step 3: Implement in `PDFHeaderTool.ahk`**

```ahk
; --- Claude API --------------------------------------------------------
BuildRequestBody(b64pdf, model) {
    static prompt := "This is one page of a medical record. Extract: "
        . "(1) date_of_service - the date this note, encounter, or study took place; never a print, fax, or signature date. "
        . "(2) provider_name - the clinician who authored or performed it, with credential if shown, like 'John Smith, MD'. "
        . "(3) note_type - a short label for the document type, like 'Office Visit', 'Operative Report', 'MRI Lumbar Spine', 'Physical Therapy', 'Discharge Summary', 'ER Visit'. "
        . "Use null for any field this page does not establish."
    static schema := '{"type":"object","properties":{'
        . '"date_of_service":{"type":["string","null"]},'
        . '"provider_name":{"type":["string","null"]},'
        . '"note_type":{"type":["string","null"]}},'
        . '"required":["date_of_service","provider_name","note_type"],'
        . '"additionalProperties":false}'
    return '{"model":"' Json.Escape(model) '","max_tokens":16000,"fallbacks":"default",'
        . '"messages":[{"role":"user","content":['
        . '{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"' b64pdf '"}},'
        . '{"type":"text","text":"' Json.Escape(prompt) '"}]}],'
        . '"output_config":{"format":{"type":"json_schema","schema":' schema '}}}'
}

ExtractFields(responseText) {
    try
        resp := Json.Parse(responseText)
    catch
        return {ok: false, err: "Unreadable API response."}
    if (resp is Map) && resp.Has("error")
        return {ok: false, err: "API error: " resp["error"]["message"]}
    if !(resp is Map) || !resp.Has("content")
        return {ok: false, err: "Unexpected API response shape."}
    if (resp.Has("stop_reason") && resp["stop_reason"] = "refusal")
        return {ok: false, err: "The model declined to read this page."}
    if (resp.Has("stop_reason") && resp["stop_reason"] = "max_tokens")
        return {ok: false, err: "The response was cut off. Try again."}
    txt := ""
    for blk in resp["content"] {
        if (blk["type"] = "text")
            txt .= blk["text"]
    }
    if (txt = "")
        return {ok: false, err: "The model returned no text."}
    try
        f := Json.Parse(txt)
    catch
        return {ok: false, err: "The model reply was not valid JSON."}
    return {ok: true, date: HDR_Field(f, "date_of_service"),
        provider: HDR_Field(f, "provider_name"),
        notetype: HDR_Field(f, "note_type")}
}

HDR_Field(m, k) {
    if !(m is Map) || !m.Has(k)
        return ""
    v := m[k]
    return (v is String) ? v : ""
}

FileToBase64(path) {
    buf := FileRead(path, "RAW")
    n := 0
    ; 0x40000001 = CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF (API forbids newlines)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", buf, "uint", buf.Size,
        "uint", 0x40000001, "ptr", 0, "uint*", &n)
    out := Buffer(n * 2)
    DllCall("crypt32\CryptBinaryToStringW", "ptr", buf, "uint", buf.Size,
        "uint", 0x40000001, "ptr", out, "uint*", &n)
    return StrGet(out, "UTF-16")
}

CallClaude(body, apiKey, timeoutSec := 60) {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("POST", "https://api.anthropic.com/v1/messages", false)
    req.SetTimeouts(15000, 15000, timeoutSec * 1000, timeoutSec * 1000)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("x-api-key", apiKey)
    req.SetRequestHeader("anthropic-version", "2023-06-01")
    req.SetRequestHeader("anthropic-beta", "server-side-fallback-2026-07-01")
    req.Send(body)
    return {status: req.Status, text: req.ResponseText}
}
```

(`CallClaude` is not unit-tested — it is exercised in Task 5's live checkpoint.)

- [ ] **Step 4: Run tests to verify all pass**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: `PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Request builder, response parser, base64, HTTP client

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Settings and toast

**Files:**
- Modify: `PDFHeaderTool.ahk`
- Modify: `tests\test_core.ahk`

**Interfaces:**
- Consumes: nothing new.
- Produces: `LoadSettings(p := "")` → `{path, firstRun, apiKey, hotkey, model, showButton, btnX, btnY}` (default path `A_AppData "\PDFHeaderTool\settings.ini"`, creates file with defaults when missing); `Toast(msg, ms := 2600)` shows a self-clearing tooltip. Ini keys: `ApiKey`, `Hotkey` (blank = none), `Model`, `ShowButton` (1/0), `ButtonX`, `ButtonY` under `[Settings]`.

- [ ] **Step 1: Append failing tests** (settings only — `Toast` is visual, verified in Task 7)

```ahk
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
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
Expected: failure/abort mentioning `LoadSettings`.

- [ ] **Step 3: Implement**

```ahk
; --- Settings and toast ------------------------------------------------
LoadSettings(p := "") {
    if (p = "")
        p := A_AppData "\PDFHeaderTool\settings.ini"
    firstRun := !FileExist(p)
    if firstRun {
        SplitPath(p, , &dir)
        DirCreate(dir)
        ; UTF-16: the Windows ini API misreads UTF-8-with-BOM files.
        FileAppend("[Settings]`n"
            . "ApiKey=`n"
            . "Hotkey=F8`n"
            . "Model=claude-opus-5`n"
            . "ShowButton=1`n"
            . "ButtonX=`n"
            . "ButtonY=`n", p, "UTF-16")
    }
    return {path: p, firstRun: firstRun,
        apiKey: Trim(IniRead(p, "Settings", "ApiKey", "")),
        hotkey: Trim(IniRead(p, "Settings", "Hotkey", "F8")),
        model: Trim(IniRead(p, "Settings", "Model", "claude-opus-5")),
        showButton: Trim(IniRead(p, "Settings", "ShowButton", "1")) = "1",
        btnX: Trim(IniRead(p, "Settings", "ButtonX", "")),
        btnY: Trim(IniRead(p, "Settings", "ButtonY", ""))}
}

Toast(msg, ms := 2600) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -ms)
}
```

- [ ] **Step 4: Run tests to verify all pass**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: `PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Settings loader with first-run creation, toast helper

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Acrobat page grab — manual checkpoint

**Files:**
- Modify: `PDFHeaderTool.ahk`
- Create: `tools\acrobat-demo.ahk`

**Interfaces:**
- Consumes: nothing new.
- Produces: `GrabCurrentPage()` → `{ok: true, pdfPath, pageNum, docName}` (pdfPath = temp one-page PDF, pageNum 1-based) or `{ok: false, err}`. Caller owns deleting `pdfPath`.

- [ ] **Step 1: Implement in `PDFHeaderTool.ahk`**

```ahk
; --- Acrobat -----------------------------------------------------------
GrabCurrentPage() {
    if !WinExist("ahk_exe Acrobat.exe")
        return {ok: false, err: "Acrobat is not running."}
    try
        app := ComObject("AcroExch.App")
    catch
        return {ok: false, err: "Could not talk to Acrobat."}
    avdoc := app.GetActiveDoc()
    if !IsObject(avdoc)
        return {ok: false, err: "No PDF is open in Acrobat."}
    pageNum := avdoc.GetAVPageView().GetPageNum()  ; 0-based
    srcPD := avdoc.GetPDDoc()
    docName := srcPD.GetFileName()
    tmp := A_Temp "\PDFHeaderTool_page.pdf"
    try FileDelete(tmp)
    newPD := ComObject("AcroExch.PDDoc")
    newPD.Create()
    if !newPD.InsertPages(-1, srcPD, pageNum, 1, 0) {
        newPD.Close()
        return {ok: false, err: "Could not extract the page."}
    }
    saved := newPD.Save(1, tmp)  ; 1 = PDSaveFull
    newPD.Close()
    if !saved
        return {ok: false, err: "Could not save the extracted page."}
    return {ok: true, pdfPath: tmp, pageNum: pageNum + 1, docName: docName}
}
```

- [ ] **Step 2: Write the demo script** — `tools\acrobat-demo.ahk`

```ahk
#Requires AutoHotkey v2.0
#Include ..\PDFHeaderTool.ahk
g := GrabCurrentPage()
if !g.ok {
    MsgBox("FAILED: " g.err, "Acrobat demo", "Icon!")
    ExitApp(1)
}
size := FileGetSize(g.pdfPath)
MsgBox("Document: " g.docName "`nPage: " g.pageNum "`nTemp file: " g.pdfPath "`nSize: " size " bytes", "Acrobat demo", "Iconi")
ExitApp(0)
```

- [ ] **Step 3: Run the automated tests (regression only)**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: still `PASSED`, exit 0 (no new unit tests; COM is not unit-testable headless).

- [ ] **Step 4: CHECKPOINT — John verifies with a real PDF**

Ask John to open any multi-page PDF in Acrobat Pro, scroll to a page past page 1, then run:
`"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tools\acrobat-demo.ahk`
Verify together: the message box shows the right file name and the page he was actually viewing, and the temp file opens in Acrobat as exactly that one page. Do not proceed until this passes.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Acrobat current-page grab with demo checkpoint script

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Live API smoke — manual checkpoint (needs John's key)

**Files:**
- Create: `tools\api-demo.ahk`

**Interfaces:**
- Consumes: `GrabCurrentPage`, `FileToBase64`, `BuildRequestBody`, `CallClaude`, `ExtractFields`, `LoadSettings`.
- Produces: confidence that the whole read path works; no new runtime functions.

- [ ] **Step 1: Write the demo script** — `tools\api-demo.ahk`

```ahk
#Requires AutoHotkey v2.0
#Include ..\PDFHeaderTool.ahk
cfg := LoadSettings()
if (cfg.apiKey = "") {
    MsgBox("No API key in " cfg.path "`n`nPaste your key after ApiKey= and run this again.", "API demo", "Icon!")
    Run('notepad.exe "' cfg.path '"')
    ExitApp(1)
}
g := GrabCurrentPage()
if !g.ok {
    MsgBox("FAILED: " g.err, "API demo", "Icon!")
    ExitApp(1)
}
b64 := FileToBase64(g.pdfPath)
FileDelete(g.pdfPath)
r := CallClaude(BuildRequestBody(b64, cfg.model), cfg.apiKey)
if (r.status != 200) {
    f := ExtractFields(r.text)
    MsgBox("HTTP " r.status "`n" (f.ok ? "" : f.err), "API demo", "Icon!")
    ExitApp(1)
}
f := ExtractFields(r.text)
if !f.ok {
    MsgBox("FAILED: " f.err, "API demo", "Icon!")
    ExitApp(1)
}
MsgBox("Page " g.pageNum " of " g.docName "`n`n"
    . "date_of_service: [" f.date "]`n"
    . "provider_name: [" f.provider "]`n"
    . "note_type: [" f.notetype "]", "API demo", "Iconi")
ExitApp(0)
```

- [ ] **Step 2: CHECKPOINT — John pastes his key**

First run of any script created `%APPDATA%\PDFHeaderTool\settings.ini` (Task 4's `LoadSettings`). Tell John: open it (the demo opens Notepad for him if the key is missing), paste the Claude API key directly after `ApiKey=`, no quotes, save. The key never goes in chat or the repo.

- [ ] **Step 3: CHECKPOINT — live extraction on real records**

John opens a real medical-record PDF in Acrobat, picks a clinic-note page, runs:
`"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tools\api-demo.ahk`
Review the three fields together on 3–5 different pages (office visit, imaging report, operative note, a scanned/faxed page). Wrong fields at this stage mean prompt tuning in `BuildRequestBody` — iterate here, where the output is visible, not later in Word. Do not proceed until John calls the accuracy acceptable.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Live API smoke script; prompt tuned on real records

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Word inserter — manual checkpoint

**Files:**
- Modify: `PDFHeaderTool.ahk`
- Create: `tools\word-demo.ahk`

**Interfaces:**
- Consumes: `BuildHeader` output shape `{text, marks}`.
- Produces: `InsertHeader(hdr)` → `{ok: true}` or `{ok: false, err}`. Inserts `hdr.text` as its own Heading 1 paragraph immediately above the paragraph containing the Word cursor; applies yellow highlight to each range in `hdr.marks`; touches nothing else.

- [ ] **Step 1: Implement in `PDFHeaderTool.ahk`**

```ahk
; --- Word --------------------------------------------------------------
InsertHeader(hdr) {
    try
        word := ComObjActive("Word.Application")
    catch
        return {ok: false, err: "Word is not running."}
    try
        doc := word.ActiveDocument
    catch
        return {ok: false, err: "No document is open in Word."}
    try {
        insertAt := word.Selection.Paragraphs.Item(1).Range.Start
        newRng := doc.Range(insertAt, insertAt)
        newRng.InsertBefore(hdr.text "`r")
        hdrRng := doc.Range(insertAt, insertAt + StrLen(hdr.text))
        hdrRng.Style := -2  ; wdStyleHeading1
        for mk in hdr.marks {
            mrng := doc.Range(insertAt + mk.start - 1, insertAt + mk.start - 1 + mk.len)
            mrng.HighlightColorIndex := 7  ; wdYellow
        }
        return {ok: true}
    } catch as e {
        return {ok: false, err: "Word rejected the insert: " e.Message}
    }
}
```

- [ ] **Step 2: Write the demo script** — `tools\word-demo.ahk`

```ahk
#Requires AutoHotkey v2.0
#Include ..\PDFHeaderTool.ahk
; Inserts two headers at the cursor: one complete, one with placeholders.
r1 := InsertHeader(BuildHeader("2023-03-14", "John Smith, MD", "Office Visit"))
r2 := InsertHeader(BuildHeader("", "Jane Doe, PA-C", ""))
msg := "Full header: " (r1.ok ? "inserted" : r1.err) "`nPlaceholder header: " (r2.ok ? "inserted" : r2.err)
MsgBox(msg, "Word demo", (r1.ok && r2.ok) ? "Iconi" : "Icon!")
ExitApp((r1.ok && r2.ok) ? 0 : 1)
```

- [ ] **Step 3: Run automated tests (regression)**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: `PASSED`, exit 0.

- [ ] **Step 4: CHECKPOINT — verify in a scratch document**

John (or the executor, if Word automation is permitted) opens a NEW blank Word document, types two ordinary paragraphs, clicks into the second one, runs:
`"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" tools\word-demo.ahk`
Verify together: two new Heading 1 lines sit above the cursor's paragraph; the em dashes render; in the second header exactly `MM/DD/YYYY` and `NOTE TYPE` are yellow-highlighted and `Jane Doe, PA-C` is not; the original paragraphs kept their style; Ctrl+Z undoes cleanly. NEVER run this against a real chronology.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Word Heading 1 inserter with selective placeholder highlight

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Wiring — hotkey, floating button, tray, end-to-end

**Files:**
- Modify: `PDFHeaderTool.ahk` (fill in `Main()`, add pipeline + GUI)
- Create: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the finished tool. `Main()` loads settings, registers the F8 hotkey (blank = none), builds the floating button, populates the tray menu. `RunInsert(*)` is the single action shared by hotkey, button, and tray.

- [ ] **Step 1: Implement pipeline and GUI in `PDFHeaderTool.ahk`** (replace the empty `Main`)

```ahk
; --- Pipeline and UI ---------------------------------------------------
global CFG := ""
global BUSY := false
global BTNGUI := ""

RunInsert(*) {
    global BUSY
    if BUSY
        return
    BUSY := true
    try
        RunInsertCore()
    catch as e
        Toast("Error: " e.Message)
    finally
        BUSY := false
}

RunInsertCore() {
    global CFG
    if (CFG.apiKey = "") {
        Toast("No API key yet. Paste it after ApiKey= in the file that just opened, save, then try again.")
        Run('notepad.exe "' CFG.path '"')
        return
    }
    g := GrabCurrentPage()
    if !g.ok {
        Toast(g.err)
        return
    }
    Toast("Reading page " g.pageNum "...")
    b64 := FileToBase64(g.pdfPath)
    try FileDelete(g.pdfPath)
    r := CallClaude(BuildRequestBody(b64, CFG.model), CFG.apiKey)
    f := ExtractFields(r.text)
    if (r.status != 200) {
        Toast(f.ok ? "API error HTTP " r.status : f.err)
        return
    }
    if !f.ok {
        Toast(f.err)
        return
    }
    hdr := BuildHeader(f.date, f.provider, f.notetype)
    w := InsertHeader(hdr)
    Toast(w.ok ? hdr.text : w.err)
}

MakeButton() {
    global CFG, BTNGUI
    BTNGUI := Gui("+AlwaysOnTop -Caption +ToolWindow", "PDF Header")
    BTNGUI.MarginX := 8
    BTNGUI.MarginY := 8
    BTNGUI.SetFont("s10 bold")
    b := BTNGUI.AddButton("w110 h34", "Insert header")
    b.OnEvent("Click", RunInsert)
    ; Drag anywhere on the window edge (the margin around the button).
    OnMessage(0x201, HDR_Drag)      ; WM_LBUTTONDOWN
    OnMessage(0x232, HDR_DragEnd)   ; WM_EXITSIZEMOVE
    if (CFG.btnX != "" && CFG.btnY != "")
        BTNGUI.Show("x" CFG.btnX " y" CFG.btnY " NoActivate")
    else
        BTNGUI.Show("NoActivate")
}

HDR_Drag(wParam, lParam, msg, hwnd) {
    global BTNGUI
    if (BTNGUI != "" && hwnd = BTNGUI.Hwnd)
        PostMessage(0xA1, 2, 0, , BTNGUI)  ; WM_NCLBUTTONDOWN, HTCAPTION
}

HDR_DragEnd(wParam, lParam, msg, hwnd) {
    global BTNGUI, CFG
    if (BTNGUI = "" || hwnd != BTNGUI.Hwnd)
        return
    WinGetPos(&x, &y, , , BTNGUI)
    IniWrite(x, CFG.path, "Settings", "ButtonX")
    IniWrite(y, CFG.path, "Settings", "ButtonY")
}

Main() {
    global CFG
    CFG := LoadSettings()
    if CFG.firstRun {
        MsgBox("Welcome. A settings file was created at:`n`n" CFG.path
            . "`n`nNotepad is opening it now - paste your Claude API key directly after ApiKey= and save. "
            . "You can also change the hotkey (blank = none) and hide the button (ShowButton=0) there.",
            "PDF Header Tool", "Iconi")
        Run('notepad.exe "' CFG.path '"')
    }
    if (CFG.hotkey != "") {
        try
            Hotkey(CFG.hotkey, RunInsert)
        catch
            MsgBox("The hotkey '" CFG.hotkey "' in settings.ini is not valid. Fix it and reload from the tray menu.",
                "PDF Header Tool", "Icon!")
    }
    if CFG.showButton
        MakeButton()
    A_TrayMenu.Insert("1&", "Insert header now", RunInsert)
    A_TrayMenu.Insert("2&", "Open settings", (*) => Run('notepad.exe "' CFG.path '"'))
    A_TrayMenu.Insert("3&", "Reload", (*) => Reload())
    Persistent(true)
}
```

- [ ] **Step 2: Run automated tests (regression — also proves the guard still holds)**

Run: `powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1; $LASTEXITCODE`
Expected: `PASSED`, exit 0, and no button window or tray icon appears during the test run.

- [ ] **Step 3: Write `README.md`**

```markdown
# PDF Header Tool

One keypress (F8) or one click while reading a medical-record PDF in Acrobat
Pro inserts a `MM/DD/YYYY — Provider — Note Type` Heading 1 at the Word
cursor. Fields the AI cannot read arrive as yellow-highlighted placeholders.

## Run

Double-click `PDFHeaderTool.ahk` (requires AutoHotkey v2). First run creates
`%APPDATA%\PDFHeaderTool\settings.ini` and opens it - paste your Claude API
key after `ApiKey=` and save.

## Settings (`%APPDATA%\PDFHeaderTool\settings.ini`)

- `ApiKey` - your Claude API key (never stored in this repo)
- `Hotkey` - default `F8`; blank disables the hotkey
- `Model` - default `claude-opus-5`
- `ShowButton` - `1` shows the floating button, `0` hides it
- `ButtonX`/`ButtonY` - remembered button position (set automatically)

## Tests

`powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
```

- [ ] **Step 4: CHECKPOINT — end-to-end with John**

1. Launch `PDFHeaderTool.ahk`. Confirm: tray icon, floating button, F8 registered (John has freed F8 in ChronologySuite's hotkey editor — remind him if the suite is running).
2. Scratch run: record PDF open in Acrobat, SCRATCH Word document open. Press F8 on a clinic-note page → header appears at cursor within a few seconds. Click the button → same. Tray "Insert header now" → same.
3. Drag the button by its edge to a corner; reload from tray; confirm it reopens where parked.
4. Failure paths: close Acrobat, press F8 → toast "Acrobat is not running." Temporarily blank the key in settings + tray Reload, press F8 → Notepad opens with the settings file; restore the key and Reload.
5. Real run: John uses it on a real case chronology for a handful of entries and judges accuracy and rhythm. Tuning feedback goes to the prompt in `BuildRequestBody` (accuracy) or hotkey/button settings (rhythm).

- [ ] **Step 5: Create the desktop shortcut**

```powershell
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut("$env:USERPROFILE\Desktop\PDF Header Tool.lnk")
$lnk.TargetPath = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$lnk.Arguments = '"C:\Users\jrvol\PDFHeaderTool\PDFHeaderTool.ahk"'
$lnk.WorkingDirectory = "C:\Users\jrvol\PDFHeaderTool"
$lnk.Save()
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Wire hotkey, floating button, tray menu; README; v1 complete

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Known limitations accepted for v1 (from spec)

- The request is synchronous: the floating button freezes for the few seconds the API call runs (Acrobat and Word are separate processes and are unaffected). The BUSY flag swallows double-presses — this stands in for the spec's "greys out while in flight" (a repaint during a blocked thread is unreliable anyway). Async is a later improvement if the freeze annoys John.
- Uses only the page on screen; no multi-page reasoning, no batch mode.
