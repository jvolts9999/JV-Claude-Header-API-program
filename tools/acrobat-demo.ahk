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
