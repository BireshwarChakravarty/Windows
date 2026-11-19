Windows tiles up to four windows across a 5120 × 1440 ultrawide display from the menu bar, and saves layouts so you can bring them back in one click.

**What's new in 1.3**
- Step-by-step Accessibility setup in the panel that notices as soon as you allow it.
- If Windows was opened from the disk image or Downloads, it offers to move itself to Applications, where macOS keeps the permission.
- Reset Permission and Relaunch buttons fix the "switched on but still asking" case.
- Builds signed with the project's certificate keep the permission across updates.

1.2 rebuilt window snapping for Chrome and other busy apps and added the activity log. See CHANGELOG.md for everything.

**Install:** open `Windows-macOS26.dmg`, drag Windows to Applications, then open it and allow it under System Settings → Privacy & Security → Accessibility. Requires macOS 26 or later on Apple silicon or a supported Intel Mac.

This build is ad hoc signed, not notarized. If macOS blocks the first launch, see [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). If you used an earlier build, remove Windows from the Accessibility list and add it again, because macOS treats each ad hoc signed build as a new app.
