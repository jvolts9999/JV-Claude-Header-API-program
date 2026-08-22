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
summary - what happened, key findings, plan - typed into Word at the cursor;
with no selection, it summarizes the current PDF page instead. Uses the same
Claude model as the header button. The summary is typed in its own font and
size (separate from the header font), configurable in Settings. Toggle the
Summarize button off in Settings (**Show Summarize button**) if you only want
the single header button.

A third button, **Queue Summary**, sits above Summarize text (shown together,
hidden together). Click it to queue the current PDF page - the label updates
to show the count, e.g. `Queue Summary (3)`. With pages queued, clicking
**Summarize text** summarizes all of them together as one combined entry
(a multi-page note), ignoring any text selection. With pages queued, pressing
**Insert header** instead reads the FIRST queued page and inserts its header
- the page stays in the queue (it's still needed for the summary run). The
queue holds up to 20 pages and clears automatically after a successful
summary; a failed attempt keeps the queue so you can retry. Right-click the
Queue button to clear it manually. The queue is session-only (not saved
between runs).

A short beep plays when a header or summary insert finishes - a higher tone
on success, a lower one on failure - so you get feedback without having to
look at the screen. Turn it off in Settings (**Completion beep**). The tray
icon's tooltip tracks calls made and an estimated cost for the session, e.g.
"PDF Header Tool - 12 calls, ~8.4 cents this session" (the cost is a rough
estimate from Anthropic's published per-token pricing, not a billing figure,
and is omitted for custom/unrecognized model strings).

## Run

Double-click `PDFHeaderTool.ahk` (requires AutoHotkey v2). First run creates
`%APPDATA%\PDFHeaderTool\settings.ini` and opens the Settings window - paste
your Claude API key there and save. Pressing the hotkey with no key saved yet
does the same thing: a toast points you at Settings, which opens for you.

## Settings

Open the Settings window from the tray icon (**Settings**, the first item) or
by right-clicking the floating button (right-clicking the Queue Summary
button itself clears the queue instead). Settings covers the hotkey (or
turning it off), a second optional hotkey for Summarize text, a third
optional hotkey for Queue Summary, the model, the header font and size, the
summary font and size, whether the header uses Heading 1 style and bold, how
many blank lines follow it, showing or hiding the floating button and the
Summarize/Queue buttons, and the completion beep. No two of the three
hotkeys can be set to the same key. The API key is set via Settings ->
**API key...**, which
opens its own small dialog (with a Show/Hide toggle to check it). Save
applies changes right away - no Reload needed.

Settings are stored in `%APPDATA%\PDFHeaderTool\settings.ini`, which stays
hand-editable if you prefer:

- `ApiKey` - your Claude API key (never stored in this repo)
- `Hotkey` - default `F8`; blank disables the hotkey
- `SummarizeHotkey` - default blank (no hotkey); triggers Summarize text (including the queue, if pages are queued)
- `QueueHotkey` - default blank (no hotkey); triggers Queue Summary (queues the current page)
- `Model` - default `claude-opus-5`; cheaper alternatives: `claude-sonnet-5` (about 1 cent/press) or `claude-haiku-4-5` (about half a cent/press). Change the line, then Reload from the tray menu.
- `HeaderFont` - default `Times New Roman`
- `HeaderSize` - default `20`
- `ApplyHeadingStyle` - `1` applies Heading 1 style to the header, `0` inserts it as plain text (font settings still apply)
- `HeaderBold` - `1` forces the header bold, `0` leaves the style's own weight untouched
- `LinesBelow` - blank lines inserted after the header, `0`-`3`, default `2`
- `SummaryFont` - default `Times New Roman`; font used for inserted summaries
- `SummarySize` - default `12`; size used for inserted summaries
- `ShowButton` - `1` shows the floating button, `0` hides it
- `ShowSummarize` - `1` shows the Summarize text and Queue Summary buttons above it, `0` hides both
- `Beep` - `1` plays a completion beep (success/failure tone) after each header or summary insert, `0` disables it
- `ButtonX`/`ButtonY` - remembered button position (set automatically)

## Tests

`powershell -ExecutionPolicy Bypass -File tests\run-tests.ps1`
