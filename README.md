# Windows

Windows is a native macOS 26+ menu bar utility for arranging up to four windows on a 5120 × 1440 external display. It detects a matching ultrawide monitor in extended mode and uses its available desktop area, including when macOS display scaling is enabled.

## Build and run

Open a built `Windows.app` on macOS 26 or later. To build from source on a Mac, open `Windows.xcodeproj` in Xcode 26 or later and run the Windows scheme. The script builds a universal application for Apple silicon and supported Intel Macs and packages it as `dist/Windows-macOS26.zip`.

```sh
./Scripts/build-app.sh
open dist/Windows.app
```

Download the same ZIP from a successful **Build Windows for macOS** run in the repository’s **Actions** tab. The build uses an ad hoc signature for local testing. Apple notarization requires a Developer ID certificate.

## Arrange windows

1. Connect the external monitor in extended mode and click the four-pane monitor icon in the menu bar. Use the display menu to select your monitor if it is missing from the panel.
2. Open **Accessibility Settings** from the panel and enable Windows under **System Settings → Privacy & Security → Accessibility**. If necessary, use the **+** button there to add the app bundle.
3. Put your windows on the external monitor. Start with **Columns**, or choose **Grid** or **Focus**. Assign the window for each numbered slot or click **Auto-fill** to fill empty slots from front to back.
4. Click **Snap 4 windows**, then use **Save layout** to name the arrangement. Choose it again from **Saved** to restore it. Windows keeps the current assignments and your saved layouts across launches.

Restoration works with open, resizable windows on the selected display in its active desktop Space. If a window is closed or its identity is ambiguous, the slot shows **Missing** until you reopen it or select a replacement. Minimum window sizes may prevent some apps from fitting a slot. The built-in display and mirrored displays are excluded.

## Previews

These design previews show the menu bar panel with example data.

- [Arrange in dark appearance](Previews/Arrange.png)
- [Arrange in light appearance](Previews/Arrange-Light.png)
- [Saved](Previews/Saved.png)
- [Menu bar icon in light and dark appearances](Previews/MenuBarIcon.png)
- [App icon](Previews/AppIcon.png)

Run `swift test` with Swift 6.2 or later to check layout geometry, window matching, and saved arrangement serialization.
