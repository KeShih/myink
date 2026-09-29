# Myink — full guide

Myink is a personal, Yoink-style drag-and-drop shelf for macOS 26 and later. When you start dragging something, a small
shelf slides in at the edge of the screen. Park files, images, links or text on it, go to the destination, and drag them
back out. You never have to arrange two windows side by side.

It is built with SwiftPM and shell scripts only, so no Xcode is needed. It is not sandboxed and has no third-party
dependencies.

## Features

- **Appears when you drag.** It is shown on the screen under the pointer, on every Space and over full-screen apps. It
  never takes focus from the frontmost app.
  - Trigger modes: *on drag start* (default), *when the drag nears the edge*, *shake the pointer*, or *never* (hotkey
    only).
  - Hold **fn** during a drag to keep the shelf away. Drags that start in excluded apps are ignored.
- **Placement.** The edge can be left (default), right, top or bottom. Alignment is start, center or end, and the size
  is S, M or L, with an optional full-length mode. An optional *near pointer* mode pops the shelf up next to the pointer.
- **When idle with items**, the shelf can stay visible (default), collapse to a thin edge tab, or hide. It hides when
  it is empty.
- **Keeps anything you drag in:**
  - Files and folders are kept by reference, so moves and renames are followed.
  - Temporary and app-private files are copied into Myink's storage. That covers screenshot thumbnails, Mail
    attachments and PDF print output. Files on removable or network volumes can optionally be copied too.
  - File promises from Photos, Mail and browsers arrive behind a spinner. Image data is saved as an image file.
  - Links, text and rich text become snippets. Dragging a snippet out gives text fields the original content, and Finder
    gets a `.webloc` or `.textClipping` file.
- **Stacks.** A multi-item drop becomes one stack (unless grouping is turned off in Settings). You can drag the whole
  stack, or expand it and drag single items. Stacks can be split and merged. Dropping something that is already on the
  shelf doesn't add it twice.
- **Drag out with Finder rules.** Files are moved on the same volume and copied across volumes. ⌥ forces a copy and ⌘
  forces a move. Once a drop succeeds, the item leaves the shelf unless it is locked or *keep after drag-out* is on.
- **Recently Removed.** Every removal can be undone. Myink keeps the last 50 items for 7 days. Long-press the hotkey to
  restore them, or use the menu.
- **Hotkey.** The default is **F5**: tap it to toggle the shelf, or hold it for 1 s to restore removed items.
- **Menu bar icon and optional Dock icon.** Both accept drops. Myink can also launch at login.
- **Automation.** It works with Services, `open -a`, a `myink` CLI, the `myink://` URL scheme, AppleScript, and "Save
  PDF to Myink" in the print dialog.

## Requirements

- macOS 26 or later (developed on macOS 27).
- Command Line Tools for Xcode, with Swift 6.2 or later (`xcode-select --install`). Xcode itself is not needed.
- For development only: `swiftlint` and `swiftformat` (`brew install swiftlint swiftformat`).

## Quick start

```sh
make cert          # once: create the local signing identity (see "Signing")
make run           # build, sign, install to ~/Applications/Myink.app and launch
```

| Command | What it does |
|---|---|
| `make cert` | Creates the local signing identity (once; see "Signing") |
| `make build` | Compiles with SwiftPM only (no app bundle) |
| `make bundle` | Builds and assembles a signed `build/Myink.app` |
| `make run` | Bundles, installs to `~/Applications` and launches Myink |
| `make install` | Bundles and installs without launching |
| `make run-fg` | Installs, then runs the installed binary in the foreground (logs go to the terminal) |
| `make test` | Runs the Swift Testing suites for `MyinkCore` |
| `make lint` | Runs SwiftLint (strict) and SwiftFormat in lint mode, and fails on any `Bundle.module` |
| `make format` | Applies SwiftFormat |
| `make logs` | Streams Myink's unified logs (`subsystem == "dev.keshi.myink"`) |
| `make install-cli` | Symlinks the `myink` CLI into `~/.local/bin` |
| `make uninstall` | Removes the app, its Launch Services registration, the PDF service and the CLI link. Shelf data is kept |
| `make reset-tcc` | Resets Myink's privacy permissions (`tccutil reset All dev.keshi.myink`) |
| `make icon` | Re-renders the app icon |
| `make clean` | Removes `.build` and `build` |

`CONFIG=release make run` builds a release configuration. `INSTALL_DIR=… make run` installs somewhere other than
`~/Applications`. To delete the shelf data as well, run `scripts/uninstall.sh --purge`.

## Signing

macOS keys privacy grants to an app's code signature. These include Files & Folders access, the per-file grants that
come with drag and drop, and the login item. An ad-hoc signature pins the exact code hash, so every rebuild looks like
a new app. The grants then get lost, and file access can fail with `EPERM` and no prompt at all.

`make cert` (`scripts/create-signing-cert.sh`) creates a stable, self-signed code-signing identity called
**Myink Local Signing**:

- The identity lives in its own keychain, `~/Library/Keychains/myink-signing.keychain-db`, and is never added to your
  login keychain.
- That keychain is protected by a random password. The password and the identity's fingerprint are stored in
  `~/.config/myink` (the directory is mode 700, the files are mode 600).
- No key material is ever written into the repository.

`scripts/bundle.sh` picks the identity up automatically. `$SIGN_IDENTITY` overrides it. Without either, the build
falls back to an ad-hoc signature and prints a warning. To check which one was used, run
`codesign -d -r- ~/Applications/Myink.app`: a stable identity shows `certificate leaf`, not `cdhash`.

To remove the identity, run `scripts/create-signing-cert.sh --remove`. The bundle ID `dev.keshi.myink` must never
change, because the grants are also keyed to it.

## Using Myink

### Dragging in and out

- Start dragging anything and the shelf appears. Drop onto the shelf to park the items there. To drop into an existing
  stack, drop onto its cell.
- Drag an item back out to any destination. A referenced file follows Finder's rules: it is moved on the same volume
  and copied to another volume.
  - Hold **⌥** to force a copy, or **⌘** to force a move.
  - Snippets and files in Myink's storage are always copied out.
- After a successful drop the item leaves the shelf, unless *keep after drag-out* is on in Settings ▸ Behavior. If you
  press Esc or the drop is refused, the drag is cancelled and the item stays.
- **Locks.** A locked item stays on the shelf after being dragged out. Click the lock on a cell to toggle it, or
  ⌥-click a lock to toggle every lock. Holding **fn** while you drag out inverts the lock for that drag.
- **fn while dragging in** keeps the shelf from appearing. You can turn this off in Settings ▸ Behavior.
- **Stacks.** A drop with several items becomes one stack, shown as a fan of thumbnails with a count. Drag the stack
  to take everything, or expand it with the chevron or a double-click and drag single items. Split and Merge are in the
  context menu. Show in Finder reveals every file in the stack.
- **Missing files.** A referenced file that was deleted, moved to the Trash or is on an unmounted drive gets a badge.
  Use "Remove Missing Items", or turn on auto-remove in Settings ▸ Behavior.

### Recently Removed

Everything that leaves the shelf goes to Recently Removed, whether it was dragged out, removed with ⌫ or cleared. Items
come back from the menu bar menu (Recently Removed ▸), or with a **long press (1 s) of the hotkey**. Each long press
restores the latest batch, and repeated long presses restore older batches. The limit and retention are set in
Settings ▸ Storage.

### Keyboard shortcuts in the shelf

These work while the shelf is showing and has a selection. Another app can stay frontmost.

| Key | Action |
|---|---|
| Space | Quick Look the selection |
| ← → ↑ ↓ | Move the selection (⇧ extends it) |
| ⌘A, or ⌥-double-click | Select all |
| Return | Open the selection |
| ⌫ | Remove the selection (to Recently Removed) |
| ⌘C | Copy the selection |
| ⌘V | Add the clipboard contents to the shelf |
| Esc | Hide the shelf |

The context menu has Open, Open With ▸, Show in Finder, Quick Look, Share ▸, Copy, Lock, Expand, Split/Merge,
Rename (owned items and snippets only), Remove and Clear All. Clear All keeps locked items; hold ⌥ to clear those too.

### Menu bar, Dock and hotkey

- Click the menu bar icon to toggle the shelf. Right-click it for Show/Hide, Recently Removed ▸, Clear, Disable
  Auto-Show, Settings… and Quit. You can also drop things onto the icon.
- The Dock icon is optional (Settings ▸ General). Files can be dropped onto it. Text and images dropped onto it arrive
  through the Service.
- The hotkey is set in Settings ▸ General. A valid shortcut is an F-key alone or includes ⌘, ⌃ or ⌥. On Apple
  keyboards the F-keys may need **fn** (for example fn-F5).
- After you hide the shelf by hand, a drag still reveals it, and it hides again afterwards.

## Automation

Every hook below goes through the same import path as a drop. None of them is destructive: `clear` moves items to
Recently Removed, and `restore` brings them back.

### Services

- **Add to Myink** takes files. Select files in Finder and choose Services ▸ Add to Myink from the context menu.
- **Add Selection to Myink** takes text, rich text, URLs and images from any app, through the app menu ▸ Services.
- To assign a shortcut, go to System Settings ▸ Keyboard ▸ Keyboard Shortcuts… ▸ Services, find the item under Files
  and Folders or Text, and double-click to record a shortcut. Settings ▸ Automation has a button that opens this pane.

### Terminal

```sh
open -a Myink ~/Downloads/report.pdf ~/Desktop/photo.png   # several files become one stack
open -g -a Myink file.txt                                   # -g: don't bring anything forward

make install-cli            # links ~/.local/bin/myink
myink add *.png             # files or folders
myink text "remember this"  # a text snippet
myink url https://example.com "Example"
myink show | hide | toggle
myink clear [--all]         # --all includes locked items
myink restore
```

### URL scheme

Run these with `open -g "myink://…"`. Percent-encode every parameter value.

| URL | Effect |
|---|---|
| `myink://add?path=/abs/a.pdf&path=~/b.png` | Add files. Paths must be absolute or start with `~/` |
| `myink://add?path=…&stack=1` | Force grouping into one stack (`stack=0` adds them separately; the default follows Settings) |
| `myink://add?url=https%3A%2F%2Fexample.com&title=Example` | Add a link snippet |
| `myink://add?text=Hello%20world` | Add a text snippet |
| `…&reveal=0` | Add silently, without showing the shelf (works with any `add`) |
| `myink://show`, `myink://hide`, `myink://toggle` | Show, hide or toggle the shelf |
| `myink://clear` | Move unlocked items to Recently Removed |
| `myink://clear?all=1` | Also move locked items |
| `myink://restore` | Restore the latest Recently Removed batch |
| `myink://settings` | Open Settings |
| `myink://quit` | Quit Myink |

Boolean parameters accept `1`, `true`, `yes` or `on`.

### AppleScript

Open Myink's dictionary in Script Editor (File ▸ Open Dictionary…) to see these commands:

```applescript
tell application "Myink"
    add POSIX file "/Users/me/Desktop/a.pdf"
    add {POSIX file "/tmp/a.txt", POSIX file "/tmp/b.txt"} with as stack
    add "a text snippet"
    show shelf
    hide shelf
    toggle shelf
    clear shelf                     -- keeps locked items
    clear shelf with including locked
    restore removed items           -- returns the number restored
    get item count                  -- read-only; a stack counts each of its items
end tell
```

Boolean parameters can also be written as `as stack true` or `including locked true`; Script Editor rewrites them to
the `with …` form when it compiles. From the shell: `osascript -e 'tell application "Myink" to get item count'`.

### Print dialog (PDF Services)

Turn on **Settings ▸ Automation ▸ Save PDF to Myink**. This places an alias to the app in `~/Library/PDF Services`.
Then choose PDF ▸ Save PDF to Myink in any print dialog, and the PDF lands on the shelf. `make uninstall` removes the
alias.

### Optional: a Finder Quick Action via Shortcuts

Myink doesn't ship a Finder extension, but you can make one in a minute with the Shortcuts app:

1. In Shortcuts, create a new shortcut, for example "Add to Myink".
2. Open the shortcut details (the ⓘ inspector). Turn on **Use as Quick Action** and **Finder**, and set it to
   **Receive Files** (and folders) in Quick Actions.
3. Add the action **Open File**. Set its input to *Shortcut Input* and its app to **Myink**.
4. Make sure **Show in Finder Quick Actions** is on.

Right-click files in Finder, choose Quick Actions ▸ Add to Myink, and they go onto the shelf. The action also appears
in the Finder preview pane.

## Project layout

```
Package.swift  Makefile  .swiftlint.yml  .swiftformat
Resources/            Info.plist, Myink.sdef, AppIcon-1024.png
scripts/              bundle.sh, install.sh, uninstall.sh, create-signing-cert.sh, make-icon.sh,
                      render-icon.swift, myink (CLI shim), dev/ (end-to-end helpers)
Sources/MyinkCore/    pure, nonisolated logic, fully unit-tested (no windows)
  Model/ Persistence/ Import/ Export/ Geometry/ Behavior/ Automation/ Hotkey/ Preferences.swift
Sources/Myink/        the AppKit app (defaultIsolation(MainActor))
  App/ Store/ Shelf/ Import/ Drag/ Hotkey/ StatusItem/ Automation/ Settings/
Tests/MyinkCoreTests/ Swift Testing suites, one per Core component
docs/                 GUIDE.md (this guide), QA.md (manual QA matrix)
```

- **`MyinkCore`** holds everything that can be tested without a window. That covers the data model and its mutations,
  persistence, the import classifier and planner, drag-out policy, edge geometry and layout, and the visibility state
  machine. It also has the drag triggers, the URL command parser, hotkey key combos and preferences.
- **`Myink`** is the AppKit app: the shelf panel and list, drag monitoring, drop handling, the status item, the hotkey,
  automation and Settings. Settings is the only part written in SwiftUI.
- **Resources live outside `Sources/`** on purpose. SwiftPM's generated `Bundle.module` looks for resources at the
  root of the `.app`, which breaks code signing. So the package declares no resources, `scripts/bundle.sh` copies
  everything into `Contents/Resources`, and the app loads it through `Bundle.main`. `make lint` fails if
  `Bundle.module` shows up anywhere.

## Development notes

The project deliberately builds with the **Command Line Tools only**. That brings a few quirks:

- **Swift Testing:** SwiftPM doesn't pass the Testing macro plugin to the compiler under the CLT, so `Package.swift`
  adds `-plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` to the test target when
  that directory exists. XCTest isn't available, so all tests use Swift Testing.
- **SwiftLint** can't load SourceKit without Xcode, so it runs with `SWIFTLINT_DISABLE_SOURCEKIT=1`. `make lint`
  already does this.
- **Macros:** only the Observation, Swift and Testing macro plugins exist. `@Observable` works. `#Preview`, `@Entry`
  and `@Previewable` don't, so don't use them. The `@State`, `@Binding` and `@Bindable` property wrappers are fine.
- **Concurrency:** the app target defaults to `MainActor` isolation. C callbacks (Carbon hotkey) and
  `NSScriptCommand` subclasses are `nonisolated` and hop with `MainActor.assumeIsolated`. Closures that run on
  background queues are `@Sendable` and hop with `Task { @MainActor in … }`.
- **Logging:** use `Log` (`Sources/Myink/App/Log.swift`), whose categories are `app`, `drag`, `shelf`, `importer`,
  `export`, `store`, `automation` and `hotkey`. `make logs` streams them.
- **No Xcode tools:** there's no `actool` or `ibtool`. The icon is rendered by `scripts/render-icon.swift` and packed
  with `sips` and `iconutil`, and the main menu is built in code.

End-to-end helpers in `scripts/dev/` (the calling terminal needs Accessibility permission):

```sh
swiftc -O -o /tmp/hiddrag scripts/dev/hiddrag.swift   # real HID mouse drag
/tmp/hiddrag 400 300 20 500 --via 200,400 --hold-ms 400 [--option] [--command] [--fn]

swiftc -O -o /tmp/axfind scripts/dev/axfind.swift     # find an element's frame via Accessibility
/tmp/axfind com.apple.finder "report.pdf" [--role AXRow]

swift scripts/dev/windows.swift Myink                 # list on-screen windows and their bounds
swiftc -O -o /tmp/axfront scripts/dev/axfront.swift   # raise an app via Accessibility
/tmp/axfront com.apple.finder

scripts/dev/e2e-drag.sh 3    # 3 rounds of Finder → shelf → Finder with real drags
```

`e2e-drag.sh` drives the real pointer and raises Finder, so run it while you're not using the Mac.
`hiddrag --front <bundle-id>` raises the source app right before pressing, which keeps an active
terminal from taking the click.

Coordinates are global CoreGraphics points, with the origin at the top-left of the main display.

## Data locations

| What | Where |
|---|---|
| Shelf manifest | `~/Library/Application Support/Myink/shelf.json` (plus `shelf.json.bak`, the last good copy) |
| Owned files and snippet data | `~/Library/Application Support/Myink/Items/<uuid>/` |
| Caches (thumbnails, Quick Look previews) | `~/Library/Caches/dev.keshi.myink/` |
| Settings | UserDefaults domain `dev.keshi.myink`, key `preferences.v1` (one JSON blob) |
| Signing identity | `~/Library/Keychains/myink-signing.keychain-db`, `~/.config/myink/` |
| PDF service alias | `~/Library/PDF Services/Save PDF to Myink` |
| Installed app | `~/Applications/Myink.app` |

To reset the settings, quit Myink and run `defaults delete dev.keshi.myink`.

## Troubleshooting

- **Services don't show up.**
  - Run `make install`, which registers the app with Launch Services and runs `pbs -update`.
  - Or run `/System/Library/CoreServices/pbs -update` yourself, then relaunch the app you're testing in.
  - Check System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services, where the items must be enabled.
  - As a last resort, log out and back in.
- **Permission prompts after every build.** The app is ad-hoc signed. Run `make cert` once, then `make run`, and
  approve the prompts one last time. If the grants got into a bad state, run `make reset-tcc` and relaunch.
- **A file can't be opened or previewed.** Look for a "missing" or "offline" badge. Files on Desktop, Documents,
  Downloads and external volumes need the matching privacy grant (System Settings ▸ Privacy & Security ▸ Files &
  Folders ▸ Myink).
- **The shelf doesn't appear when dragging.**
  - Check the trigger mode in Settings ▸ Behavior (*Never* means hotkey only), and that **Disable Auto-Show** isn't
    checked in the menu bar menu.
  - Check that the source app isn't in the excluded apps list, and that you're not holding **fn**.
  - Window drags and drags of unsupported types never trigger the shelf.
  - With the *collapse* or *hide* idle policies, look for the thin tab at the edge, or press the hotkey.
- **The hotkey does nothing.** Another app may already own the shortcut. Record a different one in Settings ▸ General.
  On Apple keyboards, try fn plus the F-key.
- **Launch at login doesn't work.** Login items only register from the installed copy in `~/Applications`. If Settings
  says approval is required, allow Myink in System Settings ▸ General ▸ Login Items. `sfltool dumpbtm` shows what is
  registered.
- **Logs.** Run `make logs`, or `make run-fg` to see output in the terminal.
