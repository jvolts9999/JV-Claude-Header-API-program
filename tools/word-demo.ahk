#Requires AutoHotkey v2.0
#Include ..\PDFHeaderTool.ahk
; Inserts two headers at the cursor: one complete, one with placeholders.
r1 := InsertHeader(BuildHeader("2023-03-14", "John Smith, MD", "Office Visit"), "Times New Roman", 20)
r2 := InsertHeader(BuildHeader("", "Jane Doe, PA-C", ""), "Times New Roman", 20)
msg := "Full header: " (r1.ok ? "inserted" : r1.err) "`nPlaceholder header: " (r2.ok ? "inserted" : r2.err)
MsgBox(msg, "Word demo", (r1.ok && r2.ok) ? "Iconi" : "Icon!")
ExitApp((r1.ok && r2.ok) ? 0 : 1)
