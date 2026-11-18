# Windows

Windows is a native macOS 26+ menu bar utility for tiling up to four windows across a 5120 × 1440 ultrawide display in one click. It detects a matching monitor in extended mode and uses its available desktop area, including when macOS display scaling is enabled.

![Arrange panel in dark appearance](Previews/Arrange.png)

## Build and run

Open a built `Windows.app` on macOS 26 or later. To build from source on a Mac, open `Windows.xcodeproj` in Xcode 26 or later and run the Windows scheme. The script builds a universal application for Apple silicon and supported Intel Macs and packages it as `dist/Windows-macOS26.zip`.

```sh
./Scripts/build-app.sh
open dist/Windows.app
```

Download the same ZIP from a successful **Build Windows for macOS** run in the repository’s **Actions** tab. The build uses an ad hoc signature for local testing. Apple notarization requires a Developer ID certificate.

## Arrange windows

1. Connect the external monitor in extended mode and click the four-column monitor icon in the menu bar. Use the display menu to select your monitor if it is missing from the panel.
2. Open **Accessibility Settings** from the panel and enable Windows under **System Settings → Privacy & Security → Accessibility**. If necessary, use the **+** button there to add the app bundle.
3. Put your windows on the external monitor and pick a layout. Assign the window for each numbered slot or click **Auto-fill** to fill empty slots from front to back. The monitor preview shows each app in the slot it will fill.
4. Click **Snap** (or press Return), then use **Save layout** to name the arrangement. Choose it again from **Saved** to restore it. Windows keeps the current assignments and your saved layouts across launches.
5. Changed your mind? Click **Undo** (or press ⌘Z) to move windows back to where they were before the last snap.

| Layout | Slots | Good for |
| --- | --- | --- |
| Halves | 2 | Two full-height apps side by side |
| Thirds | 3 | Three equal columns |
| Center | 3 | A wide main window between two side panels |
| Columns | 4 | Four equal columns |
| Grid | 4 | Two rows of two |
| Focus | 4 | A wide center window, a tall right column and two stacked windows on the left |

Assignments in slots that a smaller layout hides are kept, so switching back restores them.

Restoration works with open, resizable windows on the selected display in its active desktop Space. If a window is closed or its identity is ambiguous, the slot shows **Missing** until you reopen it or select a replacement. Minimum window sizes may prevent some apps from fitting a slot. The built-in display and mirrored displays are excluded.

## Previews

These design previews show the menu bar panel with example data and placeholder app icons.

- [Arrange in dark appearance](Previews/Arrange.png)
- [Arrange with the Center layout in light appearance](Previews/Arrange-Light.png)
- [Saved](Previews/Saved.png)
- [Menu bar icon in light and dark appearances](Previews/MenuBarIcon.png)
- [App icon](Previews/AppIcon.png) (source: [Design/AppIcon.svg](Design/AppIcon.svg))

Run `swift test` with Swift 6.2 or later to check layout geometry, window matching, and saved arrangement serialization.
