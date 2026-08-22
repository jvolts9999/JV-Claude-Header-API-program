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
    fb := (SubStr(model, 1, 13) = "claude-opus-5" || SubStr(model, 1, 12) = "claude-fable") ? '"fallbacks":"default",' : ""
    return '{"model":"' Json.Escape(model) '","max_tokens":16000,' fb
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
            . "Model=claude-opus-5`n"
            . "ShowButton=1`n"
            . "ButtonX=`n"
            . "ButtonY=`n"
            . "HeaderFont=Times New Roman`n"
            . "HeaderSize=20`n", p, "UTF-16")
    }
    return {path: p, firstRun: firstRun,
        apiKey: Trim(IniRead(p, "Settings", "ApiKey", "")),
        hotkey: Trim(IniRead(p, "Settings", "Hotkey", "F8")),
        model: Trim(IniRead(p, "Settings", "Model", "claude-opus-5")),
        showButton: Trim(IniRead(p, "Settings", "ShowButton", "1")) = "1",
        btnX: Trim(IniRead(p, "Settings", "ButtonX", "")),
        btnY: Trim(IniRead(p, "Settings", "ButtonY", "")),
        headerFont: Trim(IniRead(p, "Settings", "HeaderFont", "Times New Roman")),
        headerSize: HDR_ValidSize(Trim(IniRead(p, "Settings", "HeaderSize", "20")))}
}

HDR_ValidSize(v) {
    if (v = "" || !IsInteger(v))
        return 20
    v := Integer(v)
    return (v < 6 || v > 72) ? 20 : v
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
InsertHeader(hdr, fontName := "", fontSize := 0) {
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
        if (fontName != "" || fontSize > 0) {
            if (fontName != "")
                hdrRng.Font.Name := fontName
            if (fontSize > 0)
                hdrRng.Font.Size := fontSize
            hdrRng.Font.Color := 0  ; black - Heading1's theme color would otherwise win
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

; --- Pipeline and UI ---------------------------------------------------
global CFG := ""
global BUSY := false
global BTNGUI := ""
global PROGGUI := ""
global PROGTEXT := ""
global PROGBAR := ""
global SETGUI := ""

; Small floating status window - text + a stepping progress bar, shown
; near the mouse. PROG_Show creates the Gui once and reuses it on later runs.
PROG_Show(text) {
    global PROGGUI, PROGTEXT, PROGBAR
    if (PROGGUI = "") {
        PROGGUI := Gui("+AlwaysOnTop -Caption +ToolWindow", "PDF Header Progress")
        PROGGUI.MarginX := 10
        PROGGUI.MarginY := 8
        PROGGUI.SetFont("s9")
        PROGTEXT := PROGGUI.AddText("w260", text)
        PROGBAR := PROGGUI.AddProgress("w260 h16", 0)
    } else {
        PROGTEXT.Text := text
        PROGBAR.Value := 0
    }
    MouseGetPos(&mx, &my)
    PROGGUI.Show("x" (mx + 16) " y" (my + 16) " NoActivate")
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
    global CFG
    if (CFG.apiKey = "") {
        Toast("No API key yet. Paste it after ApiKey= in the file that just opened, save, then try again.")
        Run('notepad.exe "' CFG.path '"')
        return
    }
    PROG_Show("Reading page...")
    g := GrabCurrentPage()
    if !g.ok {
        Toast(g.err)
        return
    }
    b64 := FileToBase64(g.pdfPath)
    try FileDelete(g.pdfPath)
    askMsg := "Asking Claude (page " g.pageNum ")..."
    PROG_Set(askMsg, 10)
    pct := 10
    TickAsk() {
        pct := Min(pct + 10, 90)
        PROG_Set(askMsg, pct)
    }
    r := CallClaude(BuildRequestBody(b64, CFG.model), CFG.apiKey, , TickAsk)
    if (r.status = 0) {
        Toast(r.err)
        return
    }
    f := ExtractFields(r.text)
    if (r.status != 200) {
        Toast(f.ok ? "API error HTTP " r.status : f.err)
        return
    }
    if !f.ok {
        Toast(f.err)
        return
    }
    PROG_Set("Inserting...", 95)
    hdr := BuildHeader(f.date, f.provider, f.notetype)
    w := InsertHeader(hdr, CFG.headerFont, CFG.headerSize)
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
    BTNGUI.OnEvent("ContextMenu", (*) => ShowSettingsGui())
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

ShowSettingsGui() {
    global CFG, SETGUI, BTNGUI
    if (SETGUI != "") {
        SETGUI.Show()
        return
    }

    mo := ModelOptions()

    SETGUI := Gui("+ToolWindow", "PDF Header Tool - Settings")
    SETGUI.MarginX := 12
    SETGUI.MarginY := 10
    SETGUI.SetFont("s9")

    SETGUI.AddText("", "Hotkey:")
    try
        hkCtl := SETGUI.AddHotkey("w150 x+10 yp-2", CFG.hotkey)
    catch
        hkCtl := SETGUI.AddHotkey("w150 x+10 yp-2")
    noHotkeyChk := SETGUI.AddCheckbox("x+10 yp+2" (CFG.hotkey = "" ? " Checked" : ""), "No hotkey")
    hkCtl.Enabled := (CFG.hotkey != "")
    noHotkeyChk.OnEvent("Click", SETGUI_ToggleHotkey)
    SETGUI_ToggleHotkey(*) {
        hkCtl.Enabled := !noHotkeyChk.Value
    }

    SETGUI.AddText("xm y+12", "Model:")
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
    modelDDL.OnEvent("Change", SETGUI_ModelChanged)
    SETGUI_ModelChanged(*) {
        idx := modelDDL.Value
        modelNoteTxt.Text := (idx >= 1 && idx <= mo.Length)
            ? ModelNoteFor(mo[idx].id) : "Custom model string from settings file."
    }

    SETGUI.AddText("xm y+12", "Font:")
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
    SETGUI.AddText("x+10 yp+4", "Size:")
    sizeEdit := SETGUI.AddEdit("w60 x+6 yp-4 Number", CFG.headerSize)
    SETGUI.AddUpDown("Range6-72", CFG.headerSize)

    showBtnChk := SETGUI.AddCheckbox("xm y+14" (CFG.showButton ? " Checked" : ""), "Show floating button")

    SETGUI.AddText("xm y+12", "API key:")
    apiKeyEdit := SETGUI.AddEdit("w300 x+10 yp-2 Password", CFG.apiKey)

    saveBtn := SETGUI.AddButton("xm y+16 w90 Default", "Save")
    cancelBtn := SETGUI.AddButton("x+10 yp w90", "Cancel")
    saveBtn.OnEvent("Click", SETGUI_Save)
    SETGUI_Save(*) {
        global CFG, SETGUI, BTNGUI
        newHotkey := ""
        if !noHotkeyChk.Value {
            hkVal := hkCtl.Value
            newHotkey := (hkVal != "") ? hkVal : CFG.hotkey
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

        selIdx := modelDDL.Value
        newModel := (selIdx >= 1 && selIdx <= mo.Length) ? mo[selIdx].id : CFG.model
        newFont := fontCombo.Text
        newSize := HDR_ValidSize(sizeEdit.Text)
        newApiKey := apiKeyEdit.Text
        newShowButton := showBtnChk.Value ? true : false

        if newShowButton {
            if (BTNGUI = "")
                MakeButton()
            else
                BTNGUI.Show("NoActivate")
        } else if (BTNGUI != "")
            BTNGUI.Hide()

        IniWrite(newHotkey, CFG.path, "Settings", "Hotkey")
        IniWrite(newModel, CFG.path, "Settings", "Model")
        IniWrite(newFont, CFG.path, "Settings", "HeaderFont")
        IniWrite(newSize, CFG.path, "Settings", "HeaderSize")
        IniWrite(newShowButton ? "1" : "0", CFG.path, "Settings", "ShowButton")
        IniWrite(newApiKey, CFG.path, "Settings", "ApiKey")

        CFG.hotkey := newHotkey
        CFG.model := newModel
        CFG.headerFont := newFont
        CFG.headerSize := newSize
        CFG.showButton := newShowButton
        CFG.apiKey := newApiKey

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
    A_TrayMenu.Insert("1&", "Settings", (*) => ShowSettingsGui())
    A_TrayMenu.Insert("2&", "Insert header now", RunInsert)
    A_TrayMenu.Insert("3&", "Open settings file", (*) => Run('notepad.exe "' CFG.path '"'))
    A_TrayMenu.Insert("4&", "Reload", (*) => Reload())
    Persistent(true)
}

if (A_LineFile = A_ScriptFullPath)
    Main()
