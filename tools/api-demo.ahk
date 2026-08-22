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
    . "note_type: [" f.notetype "]`n"
    . "is_imaging: [" (f.imaging ? "true" : "false") "]", "API demo", "Iconi")
ExitApp(0)
