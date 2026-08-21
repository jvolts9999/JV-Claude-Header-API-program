# PDF Header Tool — Design

Date: 2026-08-21
Status: Draft for John's review
Replaces: the retired "Word Header AI" subsystem from ChronologySuite (removed in suite v3.57 for accuracy and workflow-friction problems).

## What it is

A single standalone AutoHotkey v2 script. While John reads a medical-record PDF in
Adobe Acrobat Pro, one keypress reads the page he is looking at, asks Claude for the
header facts, and inserts a finished chronology header into Microsoft Word at his
cursor. No connection to ChronologySuite — no shared includes, no suite hotkeys.

## The workflow

1. John has a record PDF open in Acrobat Pro and his chronology open in Word.
2. He presses the hotkey (default **F8**, changeable in settings, or "none") — or
   clicks the tool's small floating button. John is freeing F8 in ChronologySuite's
   hotkey editor himself, since this tool replaces the suite's old live-headings
   workflow that owned the key.
3. The tool asks Acrobat which document and page are on screen.
4. It extracts that one page into a temporary one-page PDF (deleted afterward).
5. It sends the page to Claude (model `claude-opus-5`) as a PDF attachment — the
   model *sees* the page the way John does. This is the accuracy fix: the old tool
   fed the AI scraped text, which fails on scanned records.
6. Claude returns three fields as machine-checked JSON: **date of service**,
   **provider name**, **note type**. Any field it cannot read confidently comes
   back empty instead of guessed.
7. The tool builds the header `MM/DD/YYYY — Provider — Note Type` and inserts it
   as a **Heading 1** paragraph at the Word cursor. Date first in MM/DD/YYYY —
   the exact shape ChronologySuite's sorter and date normalizer expect, so the
   suite's document tools keep working on chronologies this tool touches.
8. An empty field is inserted as a **yellow-highlighted placeholder**
   (`MM/DD/YYYY`, `PROVIDER`, or `NOTE TYPE`) for John to fix by hand. The tool
   never blocks or asks questions mid-flow.
9. A small on-screen toast confirms success or states the failure reason.

## Decisions

- **Language/runtime:** AutoHotkey v2 (`C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`),
  one script file. Chosen over Python because the tool's real jobs — global hotkey,
  Acrobat COM, Word COM, insert-at-cursor — are AutoHotkey's native strengths, and
  one file with one runtime is easier to own than two.
- **Location:** `C:\Users\jrvol\PDFHeaderTool\`, its own small git repo. Fully
  separate from ChronologySuite by John's request ("completely start over,
  stand-alone").
- **Model:** `claude-opus-5`, called directly over HTTPS (AutoHotkey has no official
  SDK; raw HTTP is the sanctioned path). Structured output with a strict JSON
  schema, so a malformed reply is impossible rather than merely unlikely.
  Server-side fallback is enabled: in the rare case the safety layer declines a
  page, the request automatically retries on a fallback model instead of failing.
- **Cost:** roughly 1–2 cents per keypress; a few dollars across a large case.
- **API key:** stored in `%APPDATA%\PDFHeaderTool\settings.ini` — outside the repo,
  never committed, never pasted into chat. John puts it there himself, once.
- **Acrobat access:** Acrobat Pro's automation interface (IAC/COM): active document →
  current page number → extract that page to a temp PDF. Same interface the
  ChronologySuite Acrobat module already uses successfully on this machine.
- **Word access:** Word COM. Insert a new paragraph at the selection, style it
  Heading 1, leave the following paragraph Normal — mirroring how the suite's
  header picker inserts, so the cursor rhythm feels identical.

## Components (sections of the one script)

1. **Settings** — loads `%APPDATA%\PDFHeaderTool\settings.ini`: API key, hotkey,
   model name, header separator. Creates the file with a blank key slot on first
   run and tells John where it is.
2. **Hotkey handler** — registers the configured hotkey (default F8; a blank
   setting means no hotkey); guards against double-press while a request is in
   flight.
2a. **Floating button** — a tiny always-on-top button window that triggers the
   same action as the hotkey. Draggable anywhere; its position is remembered
   between runs; can be hidden via settings (`ShowButton=0`). Greys out while a
   request is in flight.
3. **Acrobat reader** — gets the active PDF and current page via COM; extracts the
   single page to a temp file in the user temp folder; cleans up afterward.
4. **Claude client** — WinHttp POST to `/v1/messages`: base64 one-page PDF as a
   document block + a fixed instruction; strict JSON schema
   `{date_of_service, provider_name, note_type}`, each nullable; 60-second
   timeout; small max_tokens (the reply is a few dozen tokens).
5. **Header builder** — normalizes the date to MM/DD/YYYY; swaps nulls for
   placeholder text and remembers which segments need highlighting.
6. **Word inserter** — inserts the Heading 1 paragraph at the cursor, applies
   yellow highlight to placeholder segments only, restores Normal style after.
7. **Toast/errors** — 2-second tooltip near the cursor: header text on success,
   short plain-English reason on failure.

## Error handling

- Acrobat not running, or no PDF open → toast says so; nothing inserted.
- Word not running, or no document → toast says so; nothing inserted.
- API error or timeout → toast with the reason (bad key, no network, timeout);
  nothing inserted.
- Some fields unreadable → **success path**: header inserted with highlighted
  placeholders.
- Page declined by safety layer even after fallback (not expected for medical
  records) → toast says so; nothing inserted.

## Testing plan (verified with John at each stage)

1. **Plumbing, no AI:** hotkey shows a message box with the detected PDF name and
   page number, and creates the temp one-page PDF. Confirms Acrobat wiring.
2. **AI, no Word:** same, plus the Claude call — message box shows the three
   extracted fields for a real record page. Confirms accuracy before touching Word.
3. **End to end:** insert into a scratch Word document, then into a real
   chronology alongside real records. Tune the extraction prompt on whatever
   pages it gets wrong.

## Out of scope for v1

- Batch mode (whole-PDF header generation) — possible later; Python becomes the
  right tool if we go there.
- Multi-page reasoning (uses only the page on screen).
- Editing or deduplicating existing headers (the suite already has tools there).
- Any note-summary text below the header.
