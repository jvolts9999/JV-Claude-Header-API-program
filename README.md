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
- `Model` - default `claude-opus-5`; cheaper alternatives: `claude-sonnet-5` (about 1 cent/press) or `claude-haiku-4-5` (about half a cent/press). Change the line, then Reload from the tray menu.
- `ShowButton` - `1` shows the floating button, `0` hides it
- `ButtonX`/`ButtonY` - remembered button position (set automatically)

## Tests

`powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
