Windows tiles up to four windows across a 5120 × 1440 ultrawide display from the menu bar, and saves layouts so you can bring them back in one click.

**What's new in 1.2**
- Rebuilt window snapping. Windows now waits for each app to finish moving its window, retries, and handles apps such as Chrome that animate window changes in enhanced accessibility mode. Previously busy Chrome windows could be moved back to where they started.
- Windows with a minimum size larger than their slot stay at the slot instead of jumping back.
- Activity log: open it from the bottom of the panel to see what happened to every window.
- Clearer messages when a window can't shrink, doesn't respond, or isn't open.

**Install:** open `Windows-macOS26.dmg`, drag Windows to Applications, then open it and allow it under System Settings → Privacy & Security → Accessibility. Requires macOS 26 or later on Apple silicon or a supported Intel Mac.

This build is ad hoc signed, not notarized. If macOS blocks the first launch, see [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). If you used an earlier build, remove Windows from the Accessibility list and add it again, because macOS treats each ad hoc signed build as a new app.
