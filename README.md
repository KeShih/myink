# Myink

A drag-and-drop shelf for macOS, inspired by [Yoink](https://eternalstorms.at/yoink/mac/).

Start dragging anything — files, folders, images, text, links — and a shelf slides in at the edge of the screen. Drop
things on it, go wherever they need to go, and drag them back out. No more arranging two Finder windows side by side.

## Install

**From a release:** download `Myink-<version>.zip` from [Releases](https://github.com/KeShih/myink/releases), unzip,
and move `Myink.app` to `~/Applications` or `/Applications`. The app isn't notarized, so the first time either
right-click it and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine ~/Applications/Myink.app
```

**From source** (macOS 26+, only the Xcode Command Line Tools needed):

```sh
make cert   # once: creates a local signing identity so macOS remembers Myink's permissions
make run    # builds, installs to ~/Applications and launches
```

## Use

- **Drag in:** start dragging anything; the shelf appears at the left edge. Drop onto it.
- **Drag out:** drag an item to any app or folder. Files move or copy like in Finder (⌥ copies, ⌘ moves), and the item
  leaves the shelf.
- **Lock** an item (🔒 on hover) to keep it on the shelf after dragging it out.
- **Stacks:** several things dropped at once become one stack. Click the count badge to see the items inside.
- **F5** shows or hides the shelf. **Hold F5** for a second to bring back what you removed last.
- **In the shelf:** Space = Quick Look, ⌫ = remove, ⌘C / ⌘V = copy / paste, right-click for more.
- **Menu bar icon:** click to toggle the shelf, right-click for Recently Removed and Settings. You can drop onto it too.

Change the edge, size, triggers, shortcut and more in **Settings** (menu bar icon → Settings…).

## Automation

```sh
open -a Myink file.pdf                          # add files
open "myink://add?text=hello"                   # add text (also: add?url=…, add?path=…)
open "myink://show"                             # show | hide | toggle | clear | restore
osascript -e 'tell application "Myink" to add POSIX file "/path/to/file"'
```

Finder's **Services ▸ Add to Myink** works on selected files and text, and **Save PDF to Myink** can be added to the
Print dialog from Settings → Automation.

## More

See [docs/GUIDE.md](docs/GUIDE.md) for the full guide: every feature and setting, the URL scheme and AppleScript
reference, how building and signing work without Xcode, the project layout, and troubleshooting.

`make test` runs the tests, `make logs` streams the app's logs, and `make uninstall` removes the app (your shelf is
kept; add `--purge` to `scripts/uninstall.sh` to delete it too).
