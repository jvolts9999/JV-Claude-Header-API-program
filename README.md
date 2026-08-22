# PDF Header Tool

One keypress (F8) or one click while reading a medical-record PDF in Acrobat
Pro inserts a `MM/DD/YYYY — Provider — Note Type` Heading 1 at the Word
cursor. A missing date is inserted as plain MM/DD/YYYY; other missing fields
are simply omitted.
Imaging study reports (MRI, CT, X-ray, etc.) insert a two-part header - date
and study type, no provider.

A second floating button, **Summarize text**, sits directly above the header
button. Select text in the PDF in Acrobat and click it (it auto-copies the
selection - no need to press Ctrl+C yourself) to get a 2-4 sentence plain-prose
summary - what happened, key findings, plan - typed into Word at the cursor.
Uses the same Claude model as the header button. Toggle it off in Settings
(**Show Summarize button**) if you only want the single header button.

## Run

Double-click `PDFHeaderTool.ahk` (requires AutoHotkey v2). First run creates
`%APPDATA%\PDFHeaderTool\settings.ini` and opens the Settings window - paste
your Claude API key there and save. Pressing the hotkey with no key saved yet
does the same thing: a toast points you at Settings, which opens for you.

## Settings

Open the Settings window from the tray icon (**Settings**, the first item) or
by right-clicking the floating button. It covers the hotkey (or turning it
off), the model, the header font and size, whether the header uses Heading 1
style and bold, how many blank lines follow it, and showing or hiding the
floating button and the Summarize button. The API key is set via Settings ->
**API key...**, which
opens its own small dialog (with a Show/Hide toggle to check it). Save
applies changes right away - no Reload needed.

Settings are stored in `%APPDATA%\PDFHeaderTool\settings.ini`, which stays
hand-editable if you prefer:

- `ApiKey` - your Claude API key (never stored in this repo)
- `Hotkey` - default `F8`; blank disables the hotkey
- `Model` - default `claude-opus-5`; cheaper alternatives: `claude-sonnet-5` (about 1 cent/press) or `claude-haiku-4-5` (about half a cent/press). Change the line, then Reload from the tray menu.
- `HeaderFont` - default `Times New Roman`
- `HeaderSize` - default `20`
- `ApplyHeadingStyle` - `1` applies Heading 1 style to the header, `0` inserts it as plain text (font settings still apply)
- `HeaderBold` - `1` forces the header bold, `0` leaves the style's own weight untouched
- `LinesBelow` - blank lines inserted after the header, `0`-`3`, default `2`
- `ShowButton` - `1` shows the floating button, `0` hides it
- `ShowSummarize` - `1` shows the Summarize text button above it, `0` hides just that one
- `ButtonX`/`ButtonY` - remembered button position (set automatically)

## Tests

`powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
