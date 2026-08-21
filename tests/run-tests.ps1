$ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$out = Join-Path $env:TEMP "pdfheadertool_tests.out"
$err = Join-Path $env:TEMP "pdfheadertool_tests.err"
$test = Join-Path $PSScriptRoot "test_core.ahk"
$p = Start-Process -FilePath $ahk -ArgumentList "/ErrorStdOut", "`"$test`"" `
    -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
Get-Content $out -ErrorAction SilentlyContinue
Get-Content $err -ErrorAction SilentlyContinue
exit $p.ExitCode
