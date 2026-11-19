# Changelog

## 1.2

- **Rebuilt window snapping.** Windows now waits for each app to finish moving its window, retries up to three times, and gives slow apps up to 1.5 seconds to respond. Busy Chrome windows were sometimes moved back to where they started; that no longer happens.
- **Chrome and Electron apps.** Windows temporarily turns off enhanced accessibility mode, which makes these apps animate window changes, while it moves their windows.
- **Minimum sizes.** A window that can’t shrink to its slot now stays at the slot’s corner, kept on screen, instead of jumping back.
- **Clearer results.** The panel says how many windows snapped and which ones couldn’t shrink, didn’t respond, or aren’t open.
- **Activity log.** Open it from the bottom of the panel to see each window’s starting frame, target, attempts, errors and final frame. You can also show it in Finder, copy recent entries, or clear it. It’s stored at `~/Library/Logs/Windows/Windows.log`.
- Each build runs an end-to-end snapping check on a real Mac in CI.

## 1.1

- **New layouts:** Halves, Thirds and Center, alongside Columns, Grid and Focus.
- **See the plan:** the monitor preview shows each app’s icon and name in the slot it will fill.
- **Undo** the last snap with the Undo button or ⌘Z. Press Return to snap.
- The window list refreshes every time you open the panel.
- Saved layouts show their apps and a Restore button.
- New app icon and menu bar icon, drawn as an ultrawide monitor.
- The Save and Snap buttons draw solid backgrounds in light and dark mode.
- Download as a disk image (`Windows-macOS26.dmg`).

## 1.0

- First release: Columns, Grid and Focus layouts for up to four windows on a 5120 × 1440 display, saved layouts, and a menu bar panel.
