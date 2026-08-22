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

BuildHeader(dateRaw, provider, noteType, includeProvider := true) {
    sep := " " Chr(0x2014) " "
    d := NormalizeDateMDY(dateRaw)
    if (d = "")
        d := "MM/DD/YYYY"
    parts := [d]
    if includeProvider {
        p := Trim(provider)
        if (p != "")
            parts.Push(p)
    }
    n := Trim(noteType)
    if (n != "")
        parts.Push(n)
    text := ""
    for i, part in parts
        text .= (i = 1 ? "" : sep) part
    return {text: text, marks: []}
}

; --- Claude API --------------------------------------------------------
ModelWantsFallbacks(model) {
    return (SubStr(model, 1, 13) = "claude-opus-5" || SubStr(model, 1, 12) = "claude-fable")
}

BuildRequestBody(b64pdf, model) {
    static prompt := "This is one page of a medical record. Extract: "
        . "(1) date_of_service - the date this note, encounter, or study took place; never a print, fax, or signature date. "
        . "(2) provider_name - the clinician who authored or performed it, with credential if shown, like 'John Smith, MD'. "
        . "(3) note_type - a short label for the document type, like 'Office Visit', 'Operative Report', 'MRI Lumbar Spine', 'Physical Therapy', 'Discharge Summary', 'ER Visit'. "
        . "(4) is_imaging - true ONLY for imaging study reports: MRI, CT, X-ray, ultrasound, myelogram, bone scan. false for everything else, including EMG/NCS, echocardiograms, procedure notes, and clinic notes. "
        . "Use null for any field this page does not establish."
    static schema := '{"type":"object","properties":{'
        . '"date_of_service":{"type":["string","null"]},'
        . '"provider_name":{"type":["string","null"]},'
        . '"note_type":{"type":["string","null"]},'
        . '"is_imaging":{"type":"boolean"}},'
        . '"required":["date_of_service","provider_name","note_type","is_imaging"],'
        . '"additionalProperties":false}'
    fb := ModelWantsFallbacks(model) ? '"fallbacks":"default",' : ""
    return '{"model":"' Json.Escape(model) '","max_tokens":16000,' fb
        . '"messages":[{"role":"user","content":['
        . '{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"' b64pdf '"}},'
        . '{"type":"text","text":"' Json.Escape(prompt) '"}]}],'
        . '"output_config":{"format":{"type":"json_schema","schema":' schema '}}}'
}

; Sentence-count instruction shared by all three summary prompt builders,
; keyed by summary detail level (case-insensitive). Anything other than
; concise/detailed falls back to standard - same rule LoadSettings applies
; when it clamps CFG.summaryDetail.
HDR_DetailClause(level) {
    switch StrLower(Trim(level)) {
        case "concise":
            return "Write 1-2 sentences of plain prose."
        case "detailed":
            return "Write 4-8 sentences of plain prose covering what happened, the relevant history, the key findings, and the plan."
        default:
            return "Write 2-4 sentences of plain prose covering what happened, the key findings, and the plan."
    }
}

BuildSummaryRequestBody(excerpt, model, detail := "standard") {
    prompt := "Summarize the following excerpt from a medical record for a medical-legal chronology. "
        . HDR_DetailClause(detail) " "
        . "No preamble, no headings, no bullet points - just the sentences. Excerpt:"
    fb := ModelWantsFallbacks(model) ? '"fallbacks":"default",' : ""
    return '{"model":"' Json.Escape(model) '","max_tokens":16000,' fb
        . '"messages":[{"role":"user","content":['
        . '{"type":"text","text":"' Json.Escape(prompt) '\n\n' Json.Escape(excerpt) '"}]}]}'
}

BuildPageSummaryRequestBody(b64pdf, model, detail := "standard") {
    prompt := "Summarize this page of a medical record for a medical-legal chronology. "
        . HDR_DetailClause(detail) " "
        . "No preamble, no headings, no bullet points - just the sentences."
    fb := ModelWantsFallbacks(model) ? '"fallbacks":"default",' : ""
    return '{"model":"' Json.Escape(model) '","max_tokens":16000,' fb
        . '"messages":[{"role":"user","content":['
        . '{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"' b64pdf '"}},'
        . '{"type":"text","text":"' Json.Escape(prompt) '"}]}]}'
}

BuildQueueSummaryRequestBody(b64List, model, detail := "standard") {
    prompt := "These pages are one multi-page note from a medical record, in order. "
        . "Summarize the note for a medical-legal chronology. "
        . HDR_DetailClause(detail) " "
        . "No preamble, no headings, no bullet points - just the sentences."
    fb := ModelWantsFallbacks(model) ? '"fallbacks":"default",' : ""
    blocks := ""
    for b64 in b64List
        blocks .= '{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"' b64 '"}},'
    return '{"model":"' Json.Escape(model) '","max_tokens":16000,' fb
        . '"messages":[{"role":"user","content":['
        . blocks
        . '{"type":"text","text":"' Json.Escape(prompt) '"}]}]}'
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
    imaging := (f is Map && f.Has("is_imaging") && f["is_imaging"] = true) ? 1 : 0
    return {ok: true, date: HDR_Field(f, "date_of_service"),
        provider: HDR_Field(f, "provider_name"),
        notetype: HDR_Field(f, "note_type"),
        imaging: imaging}
}

ExtractText(responseText) {
    try
        resp := Json.Parse(responseText)
    catch
        return {ok: false, err: "Unreadable API response."}
    if (resp is Map) && resp.Has("error")
        return {ok: false, err: "API error: " resp["error"]["message"]}
    if !(resp is Map) || !resp.Has("content")
        return {ok: false, err: "Unexpected API response shape."}
    if (resp.Has("stop_reason") && resp["stop_reason"] = "refusal")
        return {ok: false, err: "The model declined to summarize this text."}
    if (resp.Has("stop_reason") && resp["stop_reason"] = "max_tokens")
        return {ok: false, err: "The response was cut off. Try again."}
    txt := ""
    for blk in resp["content"] {
        if (blk["type"] = "text")
            txt .= blk["text"]
    }
    txt := Trim(txt)
    if (txt = "")
        return {ok: false, err: "The model returned no text."}
    return {ok: true, text: txt}
}

; Pulls token counts out of a Claude response envelope's usage block. Missing
; usage, a missing/non-numeric field, or an unparseable response all fall
; back to zeros rather than throwing - this is purely informational (session
; cost estimate), never something that should abort a pipeline.
ExtractUsage(responseText) {
    try
        resp := Json.Parse(responseText)
    catch
        return {inTok: 0, outTok: 0}
    if !(resp is Map) || !resp.Has("usage") || !(resp["usage"] is Map)
        return {inTok: 0, outTok: 0}
    u := resp["usage"]
    inTok := (u.Has("input_tokens") && IsNumber(u["input_tokens"])) ? u["input_tokens"] : 0
    outTok := (u.Has("output_tokens") && IsNumber(u["output_tokens"])) ? u["output_tokens"] : 0
    return {inTok: inTok, outTok: outTok}
}

; Per-MTok USD rates (expressed directly in cents) by model prefix. Unknown
; model strings return -1 so callers can skip the tooltip's cost clause
; rather than show a bogus number.
EstimateCents(model, inTok, outTok) {
    if (SubStr(model, 1, StrLen("claude-opus-5")) = "claude-opus-5")
        return (inTok * 500 + outTok * 2500) / 1000000.0
    if (SubStr(model, 1, StrLen("claude-fable")) = "claude-fable")
        return (inTok * 1000 + outTok * 5000) / 1000000.0
    if (SubStr(model, 1, StrLen("claude-sonnet-5")) = "claude-sonnet-5")
        return (inTok * 300 + outTok * 1500) / 1000000.0
    if (SubStr(model, 1, StrLen("claude-haiku-4-5")) = "claude-haiku-4-5")
        return (inTok * 100 + outTok * 500) / 1000000.0
    return -1
}

; Called once per HTTP-200 response in either pipeline. Updates the session
; globals and the tray tooltip; the cost clause is omitted entirely when the
; model's pricing is unknown, rather than showing a wrong number.
HDR_TrackUsage(responseText) {
    global SESSION_CALLS, SESSION_CENTS, CFG
    SESSION_CALLS++
    u := ExtractUsage(responseText)
    cents := EstimateCents(CFG.model, u.inTok, u.outTok)
    tip := "PDF Header Tool - " SESSION_CALLS " calls"
    if (cents >= 0) {
        SESSION_CENTS += cents
        tip .= ", ~" Format("{:.1f}", SESSION_CENTS) " cents this session"
    }
    A_IconTip := tip
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

CallClaude(body, apiKey, timeoutSec := 60, onTick := "") {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    try {
        req.Open("POST", "https://api.anthropic.com/v1/messages", true)
        req.SetTimeouts(15000, 15000, timeoutSec * 1000, timeoutSec * 1000)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("x-api-key", apiKey)
        req.SetRequestHeader("anthropic-version", "2023-06-01")
        if InStr(body, '"fallbacks"')
            req.SetRequestHeader("anthropic-beta", "server-side-fallback-2026-07-01")
        req.Send(body)
    } catch as e {
        return {status: 0, text: "", err: "Could not reach the API: " e.Message}
    }
    deadline := A_TickCount + timeoutSec * 1000
    loop {
        done := false
        try
            done := req.WaitForResponse(1)
        catch
            done := false   ; 1s chunk elapsed; response not ready yet
        if done
            break
        if (A_TickCount > deadline)
            return {status: 0, text: "", err: "Timed out after " timeoutSec " seconds."}
        if (onTick != "")
            onTick.Call()
    }
    return {status: req.Status, text: req.ResponseText}
}

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
            . "SummarizeHotkey=`n"
            . "QueueHotkey=`n"
            . "Model=claude-opus-5`n"
            . "ShowButton=1`n"
            . "ShowSummarize=1`n"
            . "ButtonX=`n"
            . "ButtonY=`n"
            . "HeaderFont=Times New Roman`n"
            . "HeaderSize=20`n"
            . "ApplyHeadingStyle=1`n"
            . "HeaderBold=0`n"
            . "LinesBelow=2`n"
            . "SummaryFont=Times New Roman`n"
            . "SummarySize=12`n"
            . "SummaryDetail=standard`n"
            . "Beep=1`n"
            . "ComboInsert=1`n", p, "UTF-16")
    }
    return {path: p, firstRun: firstRun,
        apiKey: Trim(IniRead(p, "Settings", "ApiKey", "")),
        hotkey: Trim(IniRead(p, "Settings", "Hotkey", "F8")),
        summarizeHotkey: Trim(IniRead(p, "Settings", "SummarizeHotkey", "")),
        queueHotkey: Trim(IniRead(p, "Settings", "QueueHotkey", "")),
        model: Trim(IniRead(p, "Settings", "Model", "claude-opus-5")),
        showButton: Trim(IniRead(p, "Settings", "ShowButton", "1")) = "1",
        showSummarize: Trim(IniRead(p, "Settings", "ShowSummarize", "1")) = "1",
        btnX: Trim(IniRead(p, "Settings", "ButtonX", "")),
        btnY: Trim(IniRead(p, "Settings", "ButtonY", "")),
        headerFont: Trim(IniRead(p, "Settings", "HeaderFont", "Times New Roman")),
        headerSize: HDR_ValidSize(Trim(IniRead(p, "Settings", "HeaderSize", "20"))),
        applyStyle: Trim(IniRead(p, "Settings", "ApplyHeadingStyle", "1")) = "1",
        headerBold: Trim(IniRead(p, "Settings", "HeaderBold", "0")) = "1",
        linesBelow: HDR_ValidLines(Trim(IniRead(p, "Settings", "LinesBelow", "2"))),
        summaryFont: Trim(IniRead(p, "Settings", "SummaryFont", "Times New Roman")),
        summarySize: HDR_ValidSize(Trim(IniRead(p, "Settings", "SummarySize", "12")), 12),
        summaryDetail: HDR_ValidDetail(Trim(IniRead(p, "Settings", "SummaryDetail", "standard"))),
        beep: Trim(IniRead(p, "Settings", "Beep", "1")) = "1",
        comboInsert: Trim(IniRead(p, "Settings", "ComboInsert", "1")) = "1"}
}

; Canonicalizes a SummaryDetail ini value to lowercase concise/standard/detailed;
; anything else (garbage, blank, wrong case) falls back to standard.
HDR_ValidDetail(v) {
    lv := StrLower(Trim(v))
    return (lv = "concise" || lv = "detailed") ? lv : "standard"
}

HDR_ValidSize(v, fallback := 20) {
    if (v = "" || !IsInteger(v))
        return fallback
    v := Integer(v)
    return (v < 6 || v > 72) ? fallback : v
}

HDR_ValidLines(v) {
    if (v = "" || !IsInteger(v))
        return 2
    v := Integer(v)
    return (v < 0 || v > 3) ? 2 : v
}

ModelOptions() {
    return [
        {id: "claude-opus-5", label: "Opus 5 - most accurate",
            note: "Best on ugly scans and faint faxes. About 2-3 cents per press."},
        {id: "claude-sonnet-5", label: "Sonnet 5 - balanced",
            note: "Near-Opus accuracy at about a third of the cost. About 1 cent per press."},
        {id: "claude-haiku-4-5", label: "Haiku 4.5 - cheapest",
            note: "Fastest and cheapest; weakest on messy scans. About half a cent per press."}
    ]
}

ModelNoteFor(id) {
    for m in ModelOptions() {
        if (m.id = id)
            return m.note
    }
    return ""
}

Toast(msg, ms := 2600) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -ms)
}

; Completion chime for the header/summarize pipelines' outcome points only -
; a no-op when the user has turned it off in Settings.
HDR_Chime(ok) {
    global CFG
    if !CFG.beep
        return
    if ok {
        SoundBeep(523, 60)
        SoundBeep(784, 90)
    } else {
        SoundBeep(400, 80)
        SoundBeep(300, 120)
    }
}

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

; --- Word --------------------------------------------------------------
InsertHeader(hdr, fontName := "", fontSize := 0, applyStyle := true, bold := false, linesBelow := 0, fontName2 := "", fontSize2 := 0) {
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
        blankBreaks := ""
        loop linesBelow
            blankBreaks .= "`r"
        newRng.InsertBefore(hdr.text "`r" blankBreaks)
        hdrRng := doc.Range(insertAt, insertAt + StrLen(hdr.text))
        if applyStyle
            hdrRng.Style := -2  ; wdStyleHeading1
        if (fontName != "" || fontSize > 0) {
            if (fontName != "")
                hdrRng.Font.Name := fontName
            if (fontSize > 0)
                hdrRng.Font.Size := fontSize
            hdrRng.Font.Color := 0  ; black - Heading1's theme color would otherwise win
        }
        if bold
            hdrRng.Font.Bold := true
        if (linesBelow > 0) {
            ; Blank lines start right after the header's own paragraph mark
            ; and end (exclusive) where the original following paragraph now
            ; sits, so that paragraph is never touched or restyled.
            blankStart := insertAt + StrLen(hdr.text) + 1
            blankRng := doc.Range(blankStart, blankStart + linesBelow)
            blankRng.Style := -1  ; wdStyleNormal - blanks never inherit heading style
            ; Style alone doesn't clear direct character formatting (e.g. the
            ; header's own font/size survives as direct formatting on these
            ; paragraph marks) - explicitly reset the blank range to the
            ; summary font/size so what gets typed there next is body-sized.
            if (fontName2 != "" || fontSize2 > 0) {
                if (fontName2 != "")
                    blankRng.Font.Name := fontName2
                if (fontSize2 > 0)
                    blankRng.Font.Size := fontSize2
                blankRng.Font.Color := 0  ; black - matches the header range's own reset
            }
        }
        for mk in hdr.marks {
            mrng := doc.Range(insertAt + mk.start - 1, insertAt + mk.start - 1 + mk.len)
            mrng.HighlightColorIndex := 7  ; wdYellow
        }
        return {ok: true}
    } catch as e {
        return {ok: false, err: "Word rejected the insert: " e.Message}
    }
}

InsertSummary(text, fontName := "", fontSize := 0) {
    try
        word := ComObjActive("Word.Application")
    catch
        return {ok: false, err: "Word is not running."}
    try
        doc := word.ActiveDocument
    catch
        return {ok: false, err: "No document is open in Word."}
    try {
        at := word.Selection.Range.Start
        doc.Range(at, at).InsertBefore(text)
        rng := doc.Range(at, at + StrLen(text))
        if (fontName != "" || fontSize > 0) {
            if (fontName != "")
                rng.Font.Name := fontName
            if (fontSize > 0)
                rng.Font.Size := fontSize
            rng.Font.Color := 0  ; black, matching InsertHeader's font-override convention
        }
        return {ok: true}
    } catch as e {
        return {ok: false, err: "Word rejected the insert: " e.Message}
    }
}

; --- Pipeline and UI ---------------------------------------------------
global CFG := ""
global BUSY := false
global BTNGUI := ""
global PROGGUI := ""
global PROGTEXT := ""
global PROGBAR := ""
global SETGUI := ""
global SUMQUEUE := []
global QBTN := ""
global SESSION_CALLS := 0
global SESSION_CENTS := 0.0

; Small floating status window - text + a stepping progress bar, shown
; near the mouse. PROG_Show creates the Gui once and reuses it on later runs.
PROG_Show(text) {
    global PROGGUI, PROGTEXT, PROGBAR, BTNGUI
    static stripW := 260, stripInset := 6
    if (PROGGUI = "") {
        PROGGUI := Gui("+AlwaysOnTop -Caption +ToolWindow", "PDF Header Progress")
        PROGGUI.BackColor := "0x2B2B2B"
        PROGGUI.MarginX := 10
        PROGGUI.MarginY := 8
        PROGGUI.SetFont("s9")
        PROGTEXT := PROGGUI.AddText("w" stripW, text)
        PROGTEXT.SetFont("cWhite")
        PROGBAR := PROGGUI.AddProgress("w" stripW " h16", 0)
    } else {
        PROGTEXT.Text := text
        PROGBAR.Value := 0
    }
    if (BTNGUI != "" && DllCall("IsWindowVisible", "ptr", BTNGUI.Hwnd)) {
        WinGetPos(&bx, &by, &bw, &bh, BTNGUI)
        PROGTEXT.Move(6, , bw - 12)
        PROGBAR.Move(6, , bw - 12)
        PROGGUI.Show("x" bx " y" (by + bh) " w" bw " NoActivate")
    } else {
        PROGTEXT.Move(stripInset, , stripW)
        PROGBAR.Move(stripInset, , stripW)
        MouseGetPos(&mx, &my)
        PROGGUI.Show("x" (mx + 16) " y" (my + 16) " w" (stripW + stripInset * 2) " NoActivate")
    }
}

PROG_Set(text, pct) {
    global PROGGUI, PROGTEXT, PROGBAR
    if (PROGGUI = "")
        return
    PROGTEXT.Text := text
    PROGBAR.Value := pct
}

PROG_Hide() {
    global PROGGUI
    if (PROGGUI != "")
        PROGGUI.Hide()
}

RunInsert(*) {
    global BUSY
    if BUSY
        return
    BUSY := true
    try
        RunInsertCore()
    catch as e
        Toast("Error: " e.Message)
    finally {
        BUSY := false
        PROG_Hide()
    }
}

RunInsertCore() {
    global CFG, SUMQUEUE
    if (CFG.apiKey = "") {
        CFG := LoadSettings()
        if (CFG.apiKey = "") {
            Toast("No API key yet - paste it into Settings and save.")
            ShowSettingsGui()
            return false
        }
    }
    ; A non-empty queue takes priority over Acrobat's current page: the FIRST
    ; queued entry is read (and NOT deleted - the queue still owns that file,
    ; needed later for a queued summary run). Empty queue -> unchanged
    ; GrabCurrentPage path below.
    if (SUMQUEUE.Length > 0) {
        pageNum := SUMQUEUE[1].pageNum
        PROG_Show("Reading queued page " pageNum "...")
        b64 := FileToBase64(SUMQUEUE[1].pdfPath)
    } else {
        PROG_Show("Reading page...")
        g := GrabCurrentPage()
        if !g.ok {
            Toast(g.err)
            HDR_Chime(false)
            return false
        }
        b64 := FileToBase64(g.pdfPath)
        try FileDelete(g.pdfPath)
        pageNum := g.pageNum
    }
    try
        ComObjActive("Word.Application")
    catch {
        Toast("Word is not running.")
        return false
    }
    askMsg := "Asking Claude (page " pageNum ")..."
    PROG_Set(askMsg, 10)
    pct := 10
    TickAsk() {
        pct := Min(pct + 10, 90)
        PROG_Set(askMsg, pct)
    }
    r := CallClaude(BuildRequestBody(b64, CFG.model), CFG.apiKey, , TickAsk)
    if (r.status = 0) {
        Toast(r.err)
        HDR_Chime(false)
        return false
    }
    f := ExtractFields(r.text)
    if (r.status != 200) {
        Toast(f.ok ? "API error HTTP " r.status : f.err)
        HDR_Chime(false)
        return false
    }
    HDR_TrackUsage(r.text)
    if !f.ok {
        Toast(f.err)
        HDR_Chime(false)
        return false
    }
    PROG_Set("Inserting...", 95)
    hdr := BuildHeader(f.date, f.provider, f.notetype, !f.imaging)
    w := InsertHeader(hdr, CFG.headerFont, CFG.headerSize, CFG.applyStyle, CFG.headerBold, CFG.linesBelow, CFG.summaryFont, CFG.summarySize)
    Toast(w.ok ? hdr.text : w.err)
    HDR_Chime(w.ok)
    if !w.ok
        return false
    return true
}

RunSummarize(*) {
    global BUSY, CFG
    if BUSY
        return
    BUSY := true
    savedClip := ""
    try {
        ; One-press combo (default on, Settings-toggleable): the header phase
        ; runs first and must actually succeed (RunInsertCore's true/false
        ; return) before the summary phase is allowed to run. A false stop
        ; here is silent by design - the header phase already toasted/chimed
        ; its own failure, so nothing more is said.
        if (CFG.comboInsert && !RunInsertCore())
            return
        RunSummarizeCore(&savedClip)
    }
    catch as e
        Toast("Error: " e.Message)
    finally {
        BUSY := false
        PROG_Hide()
        if (savedClip != "")
            A_Clipboard := savedClip
    }
}

; savedClip is an out-param assigned the instant the real clipboard is saved,
; not a return value - so the caller's restore-in-finally holds even if this
; function throws partway through (the clipboard has already been captured
; into the caller's variable by that point, regardless of how this returns).
RunSummarizeCore(&savedClip) {
    global CFG, SUMQUEUE
    if (CFG.apiKey = "") {
        CFG := LoadSettings()
        if (CFG.apiKey = "") {
            Toast("No API key yet - paste it into Settings and save.")
            ShowSettingsGui()
            return
        }
    }
    try
        word := ComObjActive("Word.Application")
    catch {
        Toast("Word is not running.")
        return
    }

    ; Shared tail for the selected-text path, the whole-page fallback, and the
    ; queue path: ask Claude, handle the same status/ExtractText guards, insert
    ; the result. Returns true/false so the queue branch below knows whether to
    ; clear itself (only ever cleared on a confirmed successful insert).
    SummarizeAndInsert(body, progText) {
        PROG_Show(progText)
        pct := 10
        Tick() {
            pct := Min(pct + 10, 90)
            PROG_Set(progText, pct)
        }
        r := CallClaude(body, CFG.apiKey, 60, Tick)
        if (r.status = 0) {
            Toast(r.err)
            HDR_Chime(false)
            return false
        }
        t := ExtractText(r.text)
        if (r.status != 200) {
            Toast(t.ok ? "API error HTTP " r.status : t.err)
            HDR_Chime(false)
            return false
        }
        HDR_TrackUsage(r.text)
        if !t.ok {
            Toast(t.err)
            HDR_Chime(false)
            return false
        }
        ins := InsertSummary(t.text, CFG.summaryFont, CFG.summarySize)
        if !ins.ok {
            Toast(ins.err)
            HDR_Chime(false)
            return false
        }
        Toast("Summary inserted.")
        HDR_Chime(true)
        return true
    }

    ; Queue check comes BEFORE any clipboard capture, so a queued-page summary
    ; never touches the clipboard: savedClip (the caller's out-param) stays at
    ; its initial "" and RunSummarize's finally-restore is a no-op.
    if (SUMQUEUE.Length > 0) {
        n := SUMQUEUE.Length
        b64List := []
        for item in SUMQUEUE
            b64List.Push(FileToBase64(item.pdfPath))
        ok := SummarizeAndInsert(BuildQueueSummaryRequestBody(b64List, CFG.model, CFG.summaryDetail), "Summarizing " n " queued pages...")
        if ok {
            for item in SUMQUEUE
                try FileDelete(item.pdfPath)
            SUMQUEUE := []
            SUMQ_UpdateLabel()
        }
        return
    }

    savedClip := ClipboardAll()
    A_Clipboard := ""
    if WinExist("ahk_exe Acrobat.exe") && !WinActive("ahk_exe Acrobat.exe") {
        WinActivate("ahk_exe Acrobat.exe")
        Sleep(150)
    }
    Send("^c")
    ClipWait(1)
    excerpt := A_Clipboard

    if (Trim(excerpt) = "") {
        ; No selection captured - fall back to summarizing the current PDF page.
        g := GrabCurrentPage()
        if !g.ok {
            Toast(g.err)
            HDR_Chime(false)
            return
        }
        b64 := FileToBase64(g.pdfPath)
        try FileDelete(g.pdfPath)
        SummarizeAndInsert(BuildPageSummaryRequestBody(b64, CFG.model, CFG.summaryDetail), "Summarizing page " g.pageNum "...")
        return
    }
    if (StrLen(excerpt) > 200000) {
        Toast("Selection is too large.")
        return
    }
    SummarizeAndInsert(BuildSummaryRequestBody(excerpt, CFG.model, CFG.summaryDetail), "Summarizing...")
}

; SUMQUEUE label text lives on the Queue button itself; this is the one place
; that writes it, called after every push/clear/successful-queue-summary.
SUMQ_UpdateLabel() {
    global QBTN, SUMQUEUE
    if (QBTN = "")
        return
    n := SUMQUEUE.Length
    QBTN.Text := (n > 0) ? "Queue Summary (" n ")" : "Queue Summary"
}

RunQueue(*) {
    global BUSY
    if BUSY
        return
    BUSY := true
    try
        RunQueueCore()
    catch as e
        Toast("Error: " e.Message)
    finally
        BUSY := false
}

RunQueueCore() {
    global SUMQUEUE
    if (SUMQUEUE.Length >= 20) {
        Toast("Queue is full (20 pages).")
        return
    }
    g := GrabCurrentPage()
    if !g.ok {
        Toast(g.err)
        return
    }
    idx := SUMQUEUE.Length + 1
    qPath := A_Temp "\PDFHeaderTool_q" A_TickCount "_" idx ".pdf"
    try
        FileCopy(g.pdfPath, qPath, 1)
    catch as e {
        Toast("Could not queue the page: " e.Message)
        try FileDelete(g.pdfPath)
        return
    }
    try FileDelete(g.pdfPath)
    SUMQUEUE.Push({pdfPath: qPath, pageNum: g.pageNum})
    SUMQ_UpdateLabel()
    Toast("Page " g.pageNum " queued (count of " SUMQUEUE.Length ").")
}

RunQueueClear() {
    global BUSY, SUMQUEUE
    if BUSY {
        Toast("Busy - try again in a moment.")
        return
    }
    for item in SUMQUEUE
        try FileDelete(item.pdfPath)
    SUMQUEUE := []
    SUMQ_UpdateLabel()
    Toast("Queue cleared.")
}

MakeButton() {
    global CFG, BTNGUI, QBTN
    BTNGUI := Gui("+AlwaysOnTop -Caption +ToolWindow", "PDF Header")
    BTNGUI.BackColor := "0x2B2B2B"
    BTNGUI.MarginX := 8
    BTNGUI.MarginY := 8
    BTNGUI.SetFont("s10 bold")
    if CFG.showSummarize {
        QBTN := BTNGUI.AddButton("w110 h34", "Queue Summary")
        QBTN.OnEvent("Click", RunQueue)
        SUMQ_UpdateLabel()
        sb := BTNGUI.AddButton("w110 h34 y+8", "Summarize text")
        sb.OnEvent("Click", RunSummarize)
        b := BTNGUI.AddButton("w110 h34 y+8", "Insert header")
    } else {
        QBTN := ""
        b := BTNGUI.AddButton("w110 h34", "Insert header")
    }
    b.OnEvent("Click", RunInsert)
    BTNGUI.OnEvent("ContextMenu", HDR_ButtonContextMenu)
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

; Gui-level ContextMenu event: GuiCtrlObj identifies which control (if any)
; was right-clicked. The Queue button clears the queue; anywhere else opens
; Settings, same as before this button existed.
HDR_ButtonContextMenu(GuiObj, GuiCtrlObj, Item, IsRightClick, X, Y) {
    global QBTN
    if (QBTN != "" && GuiCtrlObj = QBTN)
        RunQueueClear()
    else
        ShowSettingsGui()
}

ShowSettingsGui() {
    global CFG, SETGUI, BTNGUI
    if (SETGUI != "") {
        SETGUI.Show()
        return
    }

    mo := ModelOptions()

    SETGUI := Gui("+ToolWindow", "PDF Header Tool - Settings")
    SETGUI.BackColor := "0x2B2B2B"
    SETGUI.MarginX := 12
    SETGUI.MarginY := 10
    SETGUI.SetFont("s9")
    try
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", SETGUI.Hwnd, "uint", 20, "int*", 1, "uint", 4)

    ; Labels get explicit light text per-control (SetFont("cWhite") on the
    ; returned control) rather than as the ambient default, so input controls
    ; added afterward (Edit/ComboBox/DropDownList/Hotkey) keep default/dark
    ; text on their own light system backgrounds - a blanket ambient cWhite
    ; would otherwise make those controls' text white-on-white and unreadable.
    SETGUI.AddText("", "Hotkey:").SetFont("cWhite")
    try
        hkCtl := SETGUI.AddHotkey("w150 x+10 yp-2", CFG.hotkey)
    catch
        hkCtl := SETGUI.AddHotkey("w150 x+10 yp-2")
    noHotkeyChk := SETGUI.AddCheckbox("x+10 yp+2" (CFG.hotkey = "" ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "No hotkey").SetFont("cWhite")
    hkCtl.Enabled := (CFG.hotkey != "")
    noHotkeyChk.OnEvent("Click", SETGUI_ToggleHotkey)
    SETGUI_ToggleHotkey(*) {
        hkCtl.Enabled := !noHotkeyChk.Value
    }

    SETGUI.AddText("xm y+12", "Summarize hotkey:").SetFont("cWhite")
    try
        hkCtl2 := SETGUI.AddHotkey("w150 x+10 yp-2", CFG.summarizeHotkey)
    catch
        hkCtl2 := SETGUI.AddHotkey("w150 x+10 yp-2")
    noHotkeyChk2 := SETGUI.AddCheckbox("x+10 yp+2" (CFG.summarizeHotkey = "" ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "No hotkey").SetFont("cWhite")
    hkCtl2.Enabled := (CFG.summarizeHotkey != "")
    noHotkeyChk2.OnEvent("Click", SETGUI_ToggleHotkey2)
    SETGUI_ToggleHotkey2(*) {
        hkCtl2.Enabled := !noHotkeyChk2.Value
    }

    SETGUI.AddText("xm y+12", "Queue hotkey:").SetFont("cWhite")
    try
        hkCtl3 := SETGUI.AddHotkey("w150 x+10 yp-2", CFG.queueHotkey)
    catch
        hkCtl3 := SETGUI.AddHotkey("w150 x+10 yp-2")
    noHotkeyChk3 := SETGUI.AddCheckbox("x+10 yp+2" (CFG.queueHotkey = "" ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "No hotkey").SetFont("cWhite")
    hkCtl3.Enabled := (CFG.queueHotkey != "")
    noHotkeyChk3.OnEvent("Click", SETGUI_ToggleHotkey3)
    SETGUI_ToggleHotkey3(*) {
        hkCtl3.Enabled := !noHotkeyChk3.Value
    }

    SETGUI.AddText("xm y+12", "Model:").SetFont("cWhite")
    labels := []
    for m in mo
        labels.Push(m.label)
    modelIdx := 0
    for i, m in mo {
        if (m.id = CFG.model) {
            modelIdx := i
            break
        }
    }
    if (modelIdx = 0) {
        labels.Push("Custom: " CFG.model)
        modelIdx := labels.Length
    }
    modelDDL := SETGUI.AddDropDownList("w300 x+10 yp-2 Choose" modelIdx, labels)
    modelNoteTxt := SETGUI.AddText("xm y+6 w300 r3",
        (modelIdx <= mo.Length) ? ModelNoteFor(mo[modelIdx].id) : "Custom model string from settings file.")
    modelNoteTxt.SetFont("cWhite")
    modelDDL.OnEvent("Change", SETGUI_ModelChanged)
    SETGUI_ModelChanged(*) {
        idx := modelDDL.Value
        modelNoteTxt.Text := (idx >= 1 && idx <= mo.Length)
            ? ModelNoteFor(mo[idx].id) : "Custom model string from settings file."
    }

    SETGUI.AddText("xm y+12", "Font:").SetFont("cWhite")
    fonts := ["Times New Roman", "Calibri", "Cambria", "Georgia", "Arial", "Book Antiqua"]
    fontIdx := 0
    for i, f in fonts {
        if (f = CFG.headerFont) {
            fontIdx := i
            break
        }
    }
    if (fontIdx = 0) {
        fonts.Push(CFG.headerFont)
        fontIdx := fonts.Length
    }
    fontCombo := SETGUI.AddComboBox("w200 x+10 yp-2 Choose" fontIdx, fonts)
    SETGUI.AddText("x+10 yp+4", "Size:").SetFont("cWhite")
    sizeEdit := SETGUI.AddEdit("w60 x+6 yp-4 Number", CFG.headerSize)
    SETGUI.AddUpDown("Range6-72", CFG.headerSize)

    SETGUI.AddText("xm y+12", "Summary font:").SetFont("cWhite")
    sFonts := ["Times New Roman", "Calibri", "Cambria", "Georgia", "Arial", "Book Antiqua"]
    sFontIdx := 0
    for i, f in sFonts {
        if (f = CFG.summaryFont) {
            sFontIdx := i
            break
        }
    }
    if (sFontIdx = 0) {
        sFonts.Push(CFG.summaryFont)
        sFontIdx := sFonts.Length
    }
    sFontCombo := SETGUI.AddComboBox("w200 x+10 yp-2 Choose" sFontIdx, sFonts)
    SETGUI.AddText("x+10 yp+4", "Size:").SetFont("cWhite")
    sSizeEdit := SETGUI.AddEdit("w60 x+6 yp-4 Number", CFG.summarySize)
    SETGUI.AddUpDown("Range6-72", CFG.summarySize)

    SETGUI.AddText("xm y+12", "Summary detail:").SetFont("cWhite")
    detailItems := ["Concise", "Standard", "Detailed"]
    detailLevels := ["concise", "standard", "detailed"]
    detailIdx := 2
    for i, lvl in detailLevels {
        if (lvl = CFG.summaryDetail) {
            detailIdx := i
            break
        }
    }
    detailDDL := SETGUI.AddDropDownList("w120 x+10 yp-2 Choose" detailIdx, detailItems)

    applyStyleChk := SETGUI.AddCheckbox("xm y+14" (CFG.applyStyle ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "Apply Heading 1 style").SetFont("cWhite")
    boldChk := SETGUI.AddCheckbox("x+20 yp" (CFG.headerBold ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "Bold").SetFont("cWhite")

    SETGUI.AddText("xm y+12", "Blank lines below:").SetFont("cWhite")
    linesDDL := SETGUI.AddDropDownList("w60 x+10 yp-2 Choose" (CFG.linesBelow + 1), ["0", "1", "2", "3"])

    showBtnChk := SETGUI.AddCheckbox("xm y+14" (CFG.showButton ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "Show floating button").SetFont("cWhite")
    showSummarizeChk := SETGUI.AddCheckbox("x+20 yp" (CFG.showSummarize ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "Show Summarize button").SetFont("cWhite")

    comboChk := SETGUI.AddCheckbox("xm y+14" (CFG.comboInsert ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "One press: header + summary").SetFont("cWhite")

    beepChk := SETGUI.AddCheckbox("xm y+14" (CFG.beep ? " Checked" : ""))
    SETGUI.AddText("x+4 yp", "Completion beep").SetFont("cWhite")

    pendingApiKey := CFG.apiKey
    apiKeyBtn := SETGUI.AddButton("xm y+16 w120", "API key...")
    apiKeyBtn.OnEvent("Click", SETGUI_OpenApiKey)
    SETGUI_OpenApiKey(*) {
        pendingApiKey := ShowApiKeyDialog(SETGUI, pendingApiKey)
    }

    saveBtn := SETGUI.AddButton("xm y+16 w90 Default", "Save")
    cancelBtn := SETGUI.AddButton("x+10 yp w90", "Cancel")
    saveBtn.OnEvent("Click", SETGUI_Save)
    SETGUI_Save(*) {
        global CFG, SETGUI, BTNGUI, QBTN
        newHotkey := ""
        if !noHotkeyChk.Value {
            hkVal := hkCtl.Value
            newHotkey := (hkVal != "") ? hkVal : CFG.hotkey
        }
        newSummarizeHotkey := ""
        if !noHotkeyChk2.Value {
            hkVal2 := hkCtl2.Value
            newSummarizeHotkey := (hkVal2 != "") ? hkVal2 : CFG.summarizeHotkey
        }
        newQueueHotkey := ""
        if !noHotkeyChk3.Value {
            hkVal3 := hkCtl3.Value
            newQueueHotkey := (hkVal3 != "") ? hkVal3 : CFG.queueHotkey
        }
        if ((newHotkey != "" && newSummarizeHotkey != "" && StrLower(newHotkey) = StrLower(newSummarizeHotkey))
            || (newHotkey != "" && newQueueHotkey != "" && StrLower(newHotkey) = StrLower(newQueueHotkey))
            || (newSummarizeHotkey != "" && newQueueHotkey != "" && StrLower(newSummarizeHotkey) = StrLower(newQueueHotkey))) {
            MsgBox("Each function needs its own hotkey.", "PDF Header Tool", "Icon!")
            return
        }

        oldHotkey := CFG.hotkey
        if (oldHotkey != "")
            try Hotkey(oldHotkey, "Off")
        if (newHotkey != "") {
            try {
                Hotkey(newHotkey, RunInsert, "On")
            } catch {
                if (oldHotkey != "")
                    try Hotkey(oldHotkey, RunInsert, "On")
                MsgBox("'" newHotkey "' is not a usable hotkey.", "PDF Header Tool", "Icon!")
                return
            }
        }

        oldSummarizeHotkey := CFG.summarizeHotkey
        if (oldSummarizeHotkey != "")
            try Hotkey(oldSummarizeHotkey, "Off")
        if (newSummarizeHotkey != "") {
            try {
                Hotkey(newSummarizeHotkey, RunSummarize, "On")
            } catch {
                if (oldSummarizeHotkey != "")
                    try Hotkey(oldSummarizeHotkey, RunSummarize, "On")
                MsgBox("'" newSummarizeHotkey "' is not a usable hotkey.", "PDF Header Tool", "Icon!")
                return
            }
        }

        oldQueueHotkey := CFG.queueHotkey
        if (oldQueueHotkey != "")
            try Hotkey(oldQueueHotkey, "Off")
        if (newQueueHotkey != "") {
            try {
                Hotkey(newQueueHotkey, RunQueue, "On")
            } catch {
                if (oldQueueHotkey != "")
                    try Hotkey(oldQueueHotkey, RunQueue, "On")
                MsgBox("'" newQueueHotkey "' is not a usable hotkey.", "PDF Header Tool", "Icon!")
                return
            }
        }

        selIdx := modelDDL.Value
        newModel := (selIdx >= 1 && selIdx <= mo.Length) ? mo[selIdx].id : CFG.model
        newFont := fontCombo.Text
        newSize := HDR_ValidSize(sizeEdit.Text)
        newSummaryFont := sFontCombo.Text
        newSummarySize := HDR_ValidSize(sSizeEdit.Text, 12)
        newSummaryDetail := detailLevels[detailDDL.Value]
        newApiKey := Trim(pendingApiKey)
        newShowButton := showBtnChk.Value ? true : false
        newShowSummarize := showSummarizeChk.Value ? true : false
        newApplyStyle := applyStyleChk.Value ? true : false
        newHeaderBold := boldChk.Value ? true : false
        newLinesBelow := HDR_ValidLines(linesDDL.Value - 1)
        newBeep := beepChk.Value ? true : false
        newComboInsert := comboChk.Value ? true : false

        IniWrite(newHotkey, CFG.path, "Settings", "Hotkey")
        IniWrite(newSummarizeHotkey, CFG.path, "Settings", "SummarizeHotkey")
        IniWrite(newQueueHotkey, CFG.path, "Settings", "QueueHotkey")
        IniWrite(newModel, CFG.path, "Settings", "Model")
        IniWrite(newFont, CFG.path, "Settings", "HeaderFont")
        IniWrite(newSize, CFG.path, "Settings", "HeaderSize")
        IniWrite(newSummaryFont, CFG.path, "Settings", "SummaryFont")
        IniWrite(newSummarySize, CFG.path, "Settings", "SummarySize")
        IniWrite(newSummaryDetail, CFG.path, "Settings", "SummaryDetail")
        IniWrite(newShowButton ? "1" : "0", CFG.path, "Settings", "ShowButton")
        IniWrite(newShowSummarize ? "1" : "0", CFG.path, "Settings", "ShowSummarize")
        IniWrite(newApiKey, CFG.path, "Settings", "ApiKey")
        IniWrite(newApplyStyle ? "1" : "0", CFG.path, "Settings", "ApplyHeadingStyle")
        IniWrite(newHeaderBold ? "1" : "0", CFG.path, "Settings", "HeaderBold")
        IniWrite(newLinesBelow, CFG.path, "Settings", "LinesBelow")
        IniWrite(newBeep ? "1" : "0", CFG.path, "Settings", "Beep")
        IniWrite(newComboInsert ? "1" : "0", CFG.path, "Settings", "ComboInsert")

        CFG.hotkey := newHotkey
        CFG.summarizeHotkey := newSummarizeHotkey
        CFG.queueHotkey := newQueueHotkey
        CFG.model := newModel
        CFG.headerFont := newFont
        CFG.headerSize := newSize
        CFG.summaryFont := newSummaryFont
        CFG.summarySize := newSummarySize
        CFG.summaryDetail := newSummaryDetail
        CFG.showButton := newShowButton
        CFG.showSummarize := newShowSummarize
        CFG.apiKey := newApiKey
        CFG.applyStyle := newApplyStyle
        CFG.headerBold := newHeaderBold
        CFG.linesBelow := newLinesBelow
        CFG.beep := newBeep
        CFG.comboInsert := newComboInsert

        ; Layout (single vs. stacked buttons) depends on CFG.showSummarize, so
        ; the window is always rebuilt from scratch rather than reused/shown.
        ; QBTN is reset alongside BTNGUI so it never dangles on a destroyed
        ; control if the button stays hidden (MakeButton would otherwise be
        ; the only thing that clears it, and it's skipped in that case).
        if (BTNGUI != "") {
            BTNGUI.Destroy()
            BTNGUI := ""
            QBTN := ""
        }
        if newShowButton
            MakeButton()

        SETGUI.Destroy()
        SETGUI := ""
    }
    cancelBtn.OnEvent("Click", SETGUI_Cancel)
    SETGUI.OnEvent("Close", SETGUI_Cancel)
    SETGUI_Cancel(*) {
        global SETGUI
        SETGUI.Destroy()
        SETGUI := ""
    }

    SETGUI.Show()
}

; Small owned dialog for editing the API key in isolation, so the key is
; never a control on the main Settings window. currentKey is the value to
; prefill; returns the trimmed value from OK, or currentKey unchanged on
; Cancel/Close. owner is disabled while this is open and re-enabled after.
;
; ROOT CAUSE (task 15): the old inline key Edit on the Settings window used
; "Password" with no explicit row count. AHK's AddEdit auto-sizes an Edit's
; height from its initial text when no r/h option is given; a ~100-char key
; at that width doesn't fit one line by that estimate, so AHK silently added
; ES_MULTILINE (confirmed live: ControlGetStyle showed ES_MULTILINE set,
; ES_AUTOHSCROLL cleared, and control height ballooned from ~21px to ~89px,
; overlapping Save/Cancel). Per the Win32 Edit control docs, ES_PASSWORD is
; ignored by the OS whenever ES_MULTILINE is also set - so the key rendered
; in plaintext even though the "Password" option was present and its style
; bit was in fact set. One cause, both symptoms. Fix: force a fixed single
; row (r1) below, which keeps AHK from auto-growing the control regardless
; of key length - confirmed live: same probe with r1 shows ES_MULTILINE
; cleared, ES_PASSWORD honored, height back to ~39px, no overlap.
ShowApiKeyDialog(owner, currentKey) {
    result := currentKey
    keyShowing := false

    kg := Gui("+ToolWindow +Owner" owner.Hwnd, "API Key")
    kg.BackColor := "0x2B2B2B"
    kg.MarginX := 12
    kg.MarginY := 10
    kg.SetFont("s9")
    try
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", kg.Hwnd, "uint", 20, "int*", 1, "uint", 4)

    kg.AddText("", "Claude API key:").SetFont("cWhite")
    keyEdit := kg.AddEdit("w320 r1 x+10 yp-2 Password", currentKey)
    showBtn := kg.AddButton("w50 x+6 yp-2", "Show")
    showBtn.OnEvent("Click", KEY_ToggleShow)
    KEY_ToggleShow(*) {
        keyShowing := !keyShowing
        SendMessage(0x00CC, keyShowing ? 0 : 0x25CF, 0, keyEdit)  ; EM_SETPASSWORDCHAR
        keyEdit.Redraw()
        showBtn.Text := keyShowing ? "Hide" : "Show"
    }

    okBtn := kg.AddButton("xm y+16 w90 Default", "OK")
    cancelBtn := kg.AddButton("x+10 yp w90", "Cancel")
    okBtn.OnEvent("Click", KEY_Ok)
    KEY_Ok(*) {
        result := Trim(keyEdit.Text)
        KEY_Close()
    }
    cancelBtn.OnEvent("Click", KEY_Cancel)
    kg.OnEvent("Close", KEY_Cancel)
    KEY_Cancel(*) {
        KEY_Close()
    }
    KEY_Close() {
        SendMessage(0x00CC, 0x25CF, 0, keyEdit)  ; always re-mask before close
        keyEdit.Redraw()
        kg.Destroy()
    }

    owner.Opt("+Disabled")
    kg.Show()
    WinWaitClose(kg)
    owner.Opt("-Disabled")
    return result
}

Main() {
    global CFG
    CFG := LoadSettings()
    if CFG.firstRun {
        MsgBox("Welcome. A settings file was created at:`n`n" CFG.path
            . "`n`nThe Settings window is opening now - paste your Claude API key there and save. "
            . "It also covers the hotkey, model, header style, and button.",
            "PDF Header Tool", "Iconi")
        ShowSettingsGui()
    }
    if (CFG.hotkey != "") {
        try
            Hotkey(CFG.hotkey, RunInsert)
        catch
            MsgBox("The hotkey '" CFG.hotkey "' in settings.ini is not valid. Fix it and reload from the tray menu.",
                "PDF Header Tool", "Icon!")
    }
    if (CFG.summarizeHotkey != "") {
        try
            Hotkey(CFG.summarizeHotkey, RunSummarize)
        catch
            MsgBox("The hotkey '" CFG.summarizeHotkey "' in settings.ini is not valid. Fix it and reload from the tray menu.",
                "PDF Header Tool", "Icon!")
    }
    if (CFG.queueHotkey != "") {
        try
            Hotkey(CFG.queueHotkey, RunQueue)
        catch
            MsgBox("The hotkey '" CFG.queueHotkey "' in settings.ini is not valid. Fix it and reload from the tray menu.",
                "PDF Header Tool", "Icon!")
    }
    if CFG.showButton
        MakeButton()
    A_TrayMenu.Insert("1&", "Settings", (*) => ShowSettingsGui())
    A_TrayMenu.Insert("2&", "Insert header now", RunInsert)
    A_TrayMenu.Insert("3&", "Open settings file", (*) => Run('notepad.exe "' CFG.path '"'))
    A_TrayMenu.Insert("4&", "Reload", (*) => Reload())
    Persistent(true)
}

if (A_LineFile = A_ScriptFullPath)
    Main()
