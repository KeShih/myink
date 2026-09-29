# Myink manual QA matrix

Run the whole matrix on the installed app (`make run`), at least once per milestone and before every release. Mark
each row ✅ pass, ❌ fail or ➖ not applicable. Put anything surprising in Notes, and link or file an issue for each ❌.

| | |
|---|---|
| macOS build | |
| Myink build (`CFBundleVersion`) | |
| Commit | |
| Signing (`codesign -d -r-`: certificate leaf / cdhash) | |
| Displays / Stage Manager on? | |
| Tester | |
| Date | |

Setup before a pass:

- Run `make test` and `make lint`. Both must be green.
- Start with an empty shelf and the default Settings. `defaults delete dev.keshi.myink` resets the Settings.
- Keep `make logs` running in a separate terminal.

## 1. Sources (drag in)

Expected for every row: the shelf reveals within about 150 ms of the drag start, the item shows a proper thumbnail and
name, the source app keeps focus, and the source is not modified or deleted.

| # | Source | Expected | Result | Notes |
|---|---|---|---|---|
| S1 | Finder: single file | Referenced item; rename it in Finder and the name updates | | |
| S2 | Finder: many files (5+) | One stack with a count badge, which can be expanded | | |
| S3 | Finder: folder | Referenced folder with a folder icon | | |
| S4 | Finder: file on an external drive | Referenced by default; copied when "Copy from removable/network volumes" is on | | |
| S5 | Finder: iCloud Drive file | Referenced (not copied), still opens after relaunch | | |
| S6 | Safari: link | Link snippet with title and URL | | |
| S7 | Safari: image | Owned image file, named after the page or URL | | |
| S8 | Safari: selected text | Text snippet (rich where available) | | |
| S9 | Safari: address bar URL | Link snippet with the page title | | |
| S10 | Chrome: link | Link snippet | | |
| S11 | Chrome: image | Owned image file (via promise or data), with a spinner while it arrives | | |
| S12 | Chrome: selected text | Text snippet | | |
| S13 | Photos: 1 photo | Owned image (promise), spinner then thumbnail | | |
| S14 | Photos: 10 photos | One stack of 10; all arrive, no timeout badge | | |
| S15 | Photos: video | Owned movie file that plays in Quick Look | | |
| S16 | Mail: attachment | Owned copy that survives Mail's temp cleanup | | |
| S17 | Mail: message | Owned `.eml` (or snippet); the message stays in Mail | | |
| S18 | TextEdit: rich text selection | Rich text snippet; the text stays in TextEdit | | |
| S19 | TextEdit: plain text selection | Plain text snippet; the text stays in TextEdit | | |
| S20 | Terminal: selected text | Text snippet | | |
| S21 | Screenshot floating thumbnail | Owned copy that survives after the thumbnail's temp file is gone | | |
| S22 | Duplicate drop of an item already on the shelf | Not added twice; the existing cell flashes | | |

## 2. Destinations (drag out)

Unless the row says otherwise, the item leaves the shelf after the drop and goes to Recently Removed.

| # | Destination | Expected | Result | Notes |
|---|---|---|---|---|
| D1 | Finder, same volume | File is **moved**; the item is removed from the shelf | | |
| D2 | Finder, other volume | File is **copied**; the item is removed from the shelf | | |
| D3 | Finder with ⌥ held | Forced copy (the original stays) | | |
| D4 | Finder with ⌘ held (other volume) | Forced move | | |
| D5 | Press Esc during a drag-out | Drag cancelled; the item **stays** on the shelf | | |
| D6 | Drop back onto the shelf | Reorders or merges; nothing is removed | | |
| D7 | Locked item to Finder | Copied or moved; the item stays on the shelf | | |
| D8 | Unlocked item with fn held | Stays on the shelf (lock inverted) | | |
| D9 | Stack to Finder | Every file arrives | | |
| D10 | Single child of an expanded stack | Only that file arrives; the rest of the stack stays | | |
| D11 | Mail compose window | Attached; owned files are copied out | | |
| D12 | Browser upload area (e.g. a Gmail or GitHub file drop) | Upload starts | | |
| D13 | Electron app upload (e.g. Slack or VS Code) | File is accepted; on an ambiguous result the item stays or can be restored | | |
| D14 | TextEdit document | Text snippet inserts its text; a file inserts an attachment | | |
| D15 | Terminal | Inserts the file path, or the snippet text | | |
| D16 | Text snippet to Finder | Creates a `.textClipping` | | |
| D17 | Link snippet to Finder | Creates a `.webloc` | | |
| D18 | Link snippet to a browser tab bar or address bar | Opens the URL | | |

## 3. Behaviors (visibility and triggers)

| # | Scenario | Expected | Result | Notes |
|---|---|---|---|---|
| B1 | Trigger: on drag start (default) | Reveals after a short movement | | |
| B2 | Trigger: near edge | Reveals only when the drag gets close to the shelf's edge | | |
| B3 | Trigger: shake | Reveals only after shaking the pointer mid-drag | | |
| B4 | Trigger: never | No reveal on drag; the hotkey still works | | |
| B5 | Near-pointer mode | Pops up next to the pointer, then parks at its edge | | |
| B6 | Cancelled drag (Esc or drop on nothing) | Shelf returns to its idle state | | |
| B7 | Window-title drag or text-selection drag | Never triggers the shelf | | |
| B8 | Drag from an excluded app | Never triggers the shelf | | |
| B9 | Hold fn while dragging | Shelf stays hidden; turning the setting off lets it show | | |
| B10 | Full-screen app (Safari full screen) | Shelf shows over it; the app stays frontmost | | |
| B11 | Two displays: drag on the secondary display | Shelf appears on the display under the pointer | | |
| B12 | Two displays: shelf edge is an interior edge | Reveals only after a short dwell; never bleeds onto the other display | | |
| B13 | Switch Spaces with items on the shelf | Shelf is present on every Space | | |
| B14 | Stage Manager on | Shelf shows above the stage and receives drops | | |
| B15 | Mission Control open, then closed | Shelf is unaffected and doesn't show in the window grid | | |
| B16 | Top edge on macOS 27 | Reveals early, before Mission Control's top-edge gesture | | |
| B17 | Each edge (left/right/top/bottom) × alignment × size | Placed correctly inside the visible frame | | |
| B18 | Idle: stay visible | Shelf stays shown after the drop | | |
| B19 | Idle: collapse | Collapses to a thin tab; hovering or dragging onto the tab reveals it | | |
| B20 | Idle: hide | Hides after use; the next drag or the hotkey shows it | | |
| B21 | Remove the last item | Shelf hides | | |
| B22 | Hide by hand (Esc or hotkey), then drag | A drag reveals it, and it hides again afterwards | | |
| B23 | Dark mode and light mode | Glass background, text and badges are legible in both | | |
| B24 | Reduce Motion on | Fade only, no slide | | |
| B25 | Change the display arrangement or resolution | Shelf re-places itself correctly | | |
| B26 | Disable Auto-Show (menu bar menu) | Drags no longer reveal the shelf until re-enabled | | |

## 4. Keyboard and menus

Run these with a different app frontmost, for example TextEdit, and the shelf showing.

| # | Action | Expected | Result | Notes |
|---|---|---|---|---|
| K1 | Click an item, press Space | Quick Look opens **above** the shelf; the other app stays frontmost | | |
| K2 | Arrow keys while Quick Look is open | Selection moves and the preview follows | | |
| K3 | Arrow keys (⇧ to extend) | Selection moves or extends | | |
| K4 | ⌘A | Selects all | | |
| K5 | ⌥-double-click an item | Selects all | | |
| K6 | ⌫ | Removes the selection to Recently Removed | | |
| K7 | ⌘C, then paste in TextEdit or Finder | Pastes the content or the files | | |
| K8 | ⌘V with text or files on the clipboard | Adds them to the shelf | | |
| K9 | Return | Opens the selection | | |
| K10 | Esc | Hides the shelf | | |
| K11 | Context menu: each item (Open, Open With ▸, Show in Finder, Quick Look, Share ▸, Copy, Lock, Expand, Split/Merge, Rename, Remove) | Each works | | |
| K12 | Clear All, and ⌥ Clear All | Keeps locked items; with ⌥ also clears the locked ones | | |
| K13 | ⌥-click a lock | Toggles every lock | | |
| K14 | Rename a snippet or owned file | Name persists across a relaunch; renaming is unavailable for referenced files | | |
| K15 | VoiceOver on the shelf | Cells, lock and remove buttons have meaningful labels | | |

## 5. Hotkey

| # | Action | Expected | Result | Notes |
|---|---|---|---|---|
| H1 | Tap F5 | Toggles the shelf without stealing focus | | |
| H2 | Hold F5 for 1 s after removing items | Restores the latest batch and shows the shelf | | |
| H3 | Hold again | Restores the next older batch | | |
| H4 | fn-F5 on an Apple keyboard (media-key layout) | Same as H1 and H2 | | |
| H5 | Recorder: record ⌃⌥Space | New shortcut works right away; F5 no longer does | | |
| H6 | Recorder: try a plain letter | Rejected (needs ⌘, ⌃ or ⌥, or an F-key) | | |
| H7 | Turn the hotkey off | The shortcut is released | | |

## 6. Integration and automation

| # | Hook | Expected | Result | Notes |
|---|---|---|---|---|
| I1 | Drop files on the menu bar icon | Added | | |
| I2 | Click the menu bar icon, then right-click it | Click toggles the shelf; the menu shows Show/Hide, Recently Removed ▸, Clear, Disable Auto-Show, Settings…, Quit | | |
| I3 | Dock icon on: drop files on it | Added | | |
| I4 | Dock icon on: drop selected text on it | Added through the Service | | |
| I5 | Dock icon: click (reopen) | Toggles the shelf | | |
| I6 | Finder ▸ Services ▸ Add to Myink | Selected files are added | | |
| I7 | TextEdit ▸ Services ▸ Add Selection to Myink | Selected text is added | | |
| I8 | Keyboard shortcut assigned to a Service | Works | | |
| I9 | `open -a Myink a.txt b.txt` | Adds one stack of 2 | | |
| I10 | `open -g "myink://add?path=/tmp/a.txt"` | Added | | |
| I11 | `myink://add?path=~/x&path=~/y&stack=0` | Adds 2 separate items | | |
| I12 | `myink://add?url=…&title=…` | Link snippet with that title | | |
| I13 | `myink://add?text=hello%20world` | Text snippet | | |
| I14 | `…&reveal=0` | Added without showing the shelf | | |
| I15 | `myink://show`, `hide`, `toggle` | Each works | | |
| I16 | `myink://clear`, then `myink://clear?all=1` | Unlocked items first, then all, go to Recently Removed | | |
| I17 | `myink://restore` | Latest batch comes back | | |
| I18 | `myink://settings`, `myink://quit` | Opens Settings; quits cleanly (the shelf is saved) | | |
| I19 | `myink://add?path=relative/path` or `myink://bogus` | Ignored and logged; no crash | | |
| I20 | `osascript`: `add POSIX file "…"` | Returns 1; the item is added | | |
| I21 | `osascript`: `add {…} as stack true` | One stack | | |
| I22 | `osascript`: `add "text"` | Text snippet | | |
| I23 | `osascript`: `show shelf`, `hide shelf`, `toggle shelf` | Each works | | |
| I24 | `osascript`: `clear shelf`, `clear shelf including locked true` | Items go to Recently Removed | | |
| I25 | `osascript`: `restore removed items` | Returns the count restored | | |
| I26 | `osascript -e 'tell application "Myink" to get item count'` | Correct count (stack children counted) | | |
| I27 | CLI: `myink add`, `text`, `url`, `show`, `hide`, `toggle`, `clear [--all]`, `restore` | Each works | | |
| I28 | Settings: install the PDF service, then Print ▸ PDF ▸ Save PDF to Myink | The PDF lands on the shelf as an owned file | | |
| I29 | Settings: remove the PDF service | The menu entry is gone | | |
| I30 | Finder Quick Action via a user-made Shortcut (README) | Files are added | | |
| I31 | Launch at login on, then reboot | Myink is running after login; `sfltool dumpbtm` lists it | | |
| I32 | Settings changes (every pane) | Apply live and persist across a relaunch | | |

## 7. Persistence and robustness

| # | Scenario | Expected | Result | Notes |
|---|---|---|---|---|
| P1 | Quit and relaunch with items, snippets and stacks | Everything is restored in order, with locks | | |
| P2 | `make run` (reinstall) with items on the shelf | Items survive (SIGTERM flush) | | |
| P3 | Rename or move a referenced file in Finder | The item follows it (name and path) | | |
| P4 | Delete a referenced file, or move it to the Trash | Missing/trashed badge; "Remove Missing Items" removes it | | |
| P5 | Auto-remove missing items on | Missing items disappear on the next refresh | | |
| P6 | Unmount a drive that holds a referenced file | Offline badge; after remounting it is available again | | |
| P7 | Rebuild and reinstall; open Desktop, Documents and Downloads items | No new privacy prompts (grants survive, with the `make cert` identity) | | |
| P8 | Recently Removed after the retention period or the item limit | Old entries are pruned and their owned files deleted | | |
| P9 | Corrupt `shelf.json` (write garbage, then relaunch) | App launches; restores from `.bak` or starts empty; the bad file is quarantined | | |
| P10 | Launch a second copy (`open -n`) | Only one instance keeps running | | |
| P11 | 200+ items on the shelf | Scrolling and drops stay smooth | | |
