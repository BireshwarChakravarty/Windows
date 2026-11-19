import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

private let mint = Color(red: 0.50, green: 0.93, blue: 0.80)
private let zoneColors: [Color] = [mint, Color(red: 0.51, green: 0.75, blue: 1),
                                   Color(red: 0.77, green: 0.67, blue: 1),
                                   Color(red: 1, green: 0.77, blue: 0.53)]
private let lightZoneInks: [Color] = [Color(red: 0.05, green: 0.36, blue: 0.30),
                                      Color(red: 0.11, green: 0.31, blue: 0.56),
                                      Color(red: 0.38, green: 0.23, blue: 0.58),
                                      Color(red: 0.53, green: 0.29, blue: 0.07)]

struct MenuPanel: View {
    private enum Tab: String, CaseIterable { case arrange = "Arrange", saved = "Saved" }

    let model: AppModel
    @State private var tab: Tab
    @State private var naming = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive

    init(model: AppModel, showingSaved: Bool = false) {
        self.model = model
        _tab = State(initialValue: showingSaved ? .saved : .arrange)
    }

    private var slotInks: [Color] { colorScheme == .dark ? zoneColors : lightZoneInks }
    private var accent: Color { slotInks[0] }
    private var secondaryInk: Color { .secondary }
    private var primaryButton: PillButtonStyle { PillButtonStyle(prominent: true, accent: accent, dark: colorScheme == .dark) }
    private var secondaryButton: PillButtonStyle { PillButtonStyle(prominent: false, accent: accent, dark: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 16)
            tabs
                .padding(.bottom, 14)

            if tab == .arrange {
                arrangementPanel
            } else {
                savedPanel
            }

            footer
                .padding(.top, 13)
        }
        .padding(18)
        .frame(width: 432)
        .tint(accent)
        .onAppear { model.refresh() }
        // The menu bar panel is reused between openings, so refresh each time it comes forward.
        .onChange(of: appearsActive) { _, active in
            if active { model.refresh() }
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in model.checkAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.refresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: MenuMark.image)
                .resizable()
                .renderingMode(.template)
                .frame(width: 23, height: 16)
                .foregroundStyle(accent)
                .frame(width: 43, height: 43)
                .background(accent.opacity(0.11), in: .rect(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(accent.opacity(0.24)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Windows")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .accessibilityAddTraits(.isHeader)
                Text("Ultrawide window layouts")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryInk)
            }
            Spacer(minLength: 8)
            displayMenu
        }
    }

    private var displayMenu: some View {
        Menu {
            if model.displays.isEmpty {
                Text("Connect an external display in extended mode")
            }
            ForEach(model.displays) { display in
                Button {
                    model.select(display)
                } label: {
                    if model.display == display {
                        Label("\(display.name) · \(display.resolution)", systemImage: "checkmark")
                    } else {
                        Text("\(display.name) · \(display.resolution)")
                    }
                }
                .disabled(model.busy)
            }
            Divider()
            Button("Refresh displays", action: model.refresh)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.display == nil ? secondaryInk : accent)
                    .frame(width: 6, height: 6)
                Text(model.display == nil ? "Select display" : "Display connected")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(model.display == nil ? secondaryInk : accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(accent.opacity(0.10), in: .capsule)
            .overlay { Capsule().strokeBorder(accent.opacity(0.28)) }
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("External display")
        .help(model.display?.name ?? "Choose the external display to use")
    }

    private var tabs: some View {
        Picker("Panel", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.large)
        .onChange(of: tab) { naming = false }
    }

    private var arrangementPanel: some View {
        VStack(spacing: 12) {
            monitorPreview

            if model.display == nil {
                callout("display", title: model.displayWasSelected ? "External display disconnected" : "Choose your external display",
                        detail: "Connect your monitor in extended mode to arrange windows on it.")
            } else if !model.trusted {
                callout("lock.shield", title: "Allow window control", detail: "Enable Windows in Accessibility so it can move and resize windows.") {
                    Button("Open Accessibility Settings", action: model.openAccessibility)
                        .buttonStyle(primaryButton)
                }
            } else {
                layoutPicker
                windowSlots
                if naming { saveForm }
                if model.message != nil || model.canUndo { statusRow }
                actionBar
            }
        }
    }

    private var monitorPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(model.display?.name ?? "Ultrawide display", systemImage: "display")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(model.display?.resolution ?? "5120 × 1440")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.74))
            }

            VStack(spacing: 0) {
                ZoneMap(layout: model.arrangement.layout, filled: Set(model.matches.keys), numbered: true,
                        assignments: previewAssignments)
                    .padding(6)
                    .frame(height: 104)
                    .animation(.snappy(duration: 0.28), value: model.arrangement.layout)
                    .background(.black.opacity(0.67), in: .rect(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.21)) }
                UnevenRoundedRectangle(bottomLeadingRadius: 2, bottomTrailingRadius: 2)
                    .fill(.white.opacity(0.20))
                    .frame(width: 21, height: 6)
                Capsule().fill(.white.opacity(0.23)).frame(width: 51, height: 2)
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.23),
                                              Color(red: 0.09, green: 0.12, blue: 0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.10)) }
    }

    /// Live windows where they are matched, otherwise the remembered window, so the preview shows the plan.
    private var previewAssignments: [Int: WindowReference] {
        var result = model.arrangement.activeSlots
        for (slot, window) in model.matches { result[slot] = window.reference }
        return result
    }

    private var layoutPicker: some View {
        HStack(spacing: 5) {
            ForEach(Layout.allCases) { layout in
                let selected = model.arrangement.layout == layout
                Button {
                    model.select(layout)
                } label: {
                    VStack(spacing: 6) {
                        ZoneMap(layout: layout, monochrome: selected ? accent : secondaryInk)
                            .frame(width: 34, height: 13)
                            .accessibilityHidden(true)
                        Text(layout.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? accent : secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(selected ? accent.opacity(0.10) : Color.primary.opacity(0.045), in: .rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? accent.opacity(0.32) : Color.primary.opacity(0.08)) }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                .help("\(layout.name): \(layout.slotCount) windows")
                .accessibilityLabel("\(layout.name), \(layout.slotCount) windows")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout")
    }

    private var windowSlots: some View {
        VStack(spacing: 3) {
            HStack(spacing: 7) {
                Text("Windows")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("\(model.matches.count)/\(model.arrangement.layout.slotCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryInk)
                    .accessibilityLabel("\(model.matches.count) of \(model.arrangement.layout.slotCount) windows available")
                Spacer()
                Button("Auto-fill", action: model.fill)
                    .buttonStyle(.plain)
                    .foregroundStyle(model.canFill ? accent : secondaryInk.opacity(0.48))
                    .disabled(!model.canFill)
                    .help("Fill empty slots with windows on this display, from front to back")
                Button(action: model.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 21)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(secondaryInk)
                .disabled(model.busy)
                .help("Refresh windows")
                .accessibilityLabel("Refresh windows")
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.bottom, 2)

            ForEach(model.arrangement.layout.zones.indices, id: \.self) { slot in slotMenu(slot) }

            if model.windows.isEmpty, !model.busy {
                Text("Open windows on this display, then refresh.")
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private func slotMenu(_ slot: Int) -> some View {
        let live = model.matches[slot]?.reference
        let reference = live ?? model.arrangement.slots[slot]
        let label = reference.map { $0.title.isEmpty ? $0.appName : $0.title } ?? "Choose a window"

        return Menu {
            if model.windows.isEmpty { Text("No available windows on this display") }
            ForEach(model.windows) { window in
                let reference = window.reference
                let title = reference.title.isEmpty ? reference.appName : "\(reference.appName) · \(reference.title)"
                Button {
                    model.assign(window, to: slot)
                } label: {
                    if live?.sessionID == window.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
            if reference != nil {
                Divider()
                Button("Clear slot", action: { model.clear(slot) })
            }
        } label: {
            HStack(spacing: 8) {
                Text("\(slot + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(slotInks[slot])
                    .frame(width: 20, height: 20)
                    .background(slotInks[slot].opacity(0.12), in: .rect(cornerRadius: 5))
                if let reference {
                    AppIcon(appID: reference.appID, size: 16)
                        .opacity(live == nil ? 0.45 : 1)
                        .saturation(live == nil ? 0 : 1)
                }
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(reference == nil ? secondaryInk : .primary)
                Spacer(minLength: 2)
                if let reference {
                    Text(live == nil ? "Missing" : reference.appName)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .frame(maxWidth: 102, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(live == nil ? slotInks[3] : secondaryInk)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(secondaryInk)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .frame(height: 29)
            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(model.busy)
        .accessibilityLabel("Slot \(slot + 1), \(label)")
        .accessibilityValue(reference != nil && live == nil ? "Missing" : "")
    }

    private var actionBar: some View {
        HStack(spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { naming.toggle() }
                if naming { nameFocused = true }
            } label: {
                Label(naming ? "Cancel" : "Save layout", systemImage: naming ? "xmark" : "bookmark")
            }
            .buttonStyle(secondaryButton)
            .disabled(model.assignedCount == 0 || model.busy)

            Button(action: model.snap) {
                let count = model.assignedCount
                HStack(spacing: 6) {
                    if model.busy {
                        ProgressView().controlSize(.small).scaleEffect(0.65).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    Text(count == 0 ? "Snap windows" : count == 1 ? "Snap 1 window" : "Snap \(count) windows")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(primaryButton)
            .disabled(!model.canSnap)
            .keyboardShortcut(naming ? nil : KeyboardShortcut.defaultAction)
            .help("Snap the assigned windows into place (Return)")
        }
        .controlSize(.large)
    }

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let message = model.message {
                resultLine(message)
            } else {
                Spacer(minLength: 0)
            }
            if model.canUndo {
                Button(action: model.undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.12), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .keyboardShortcut("z", modifiers: .command)
                .help("Move windows back to where they were before the last snap (⌘Z)")
            }
        }
    }

    private var saveForm: some View {
        HStack(spacing: 7) {
            TextField("Arrangement name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
            Button(model.hasSavedLayout(named: name) ? "Update" : "Save", action: save)
                .buttonStyle(PillButtonStyle(prominent: true, accent: accent, dark: colorScheme == .dark, height: 26))
                .disabled(!canSaveName)
        }
    }

    private var canSaveName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy
            && model.assignedCount > 0
    }

    private func save() {
        guard canSaveName else { return }
        model.save(as: name)
        name = ""
        naming = false
    }

    private var savedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved layouts")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            if model.saved.isEmpty {
                callout("bookmark", title: "No saved layouts yet", detail: "Assign windows in Arrange and save the layout to bring it back later.") {
                    Button("Arrange windows") { tab = .arrange }
                        .buttonStyle(primaryButton)
                }
            } else {
                if model.display == nil || !model.trusted {
                    Text("A layout will load into Arrange. Connect the external display and allow window control to snap it.")
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryInk)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.saved.sorted(by: { $0.savedAt > $1.savedAt })) { entry in
                            savedRow(entry)
                        }
                    }
                }
                .frame(height: min(360, CGFloat(model.saved.count * 43 - 6)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func savedRow(_ entry: SavedArrangement) -> some View {
        HStack(spacing: 8) {
            Button {
                tab = .arrange
                model.restore(entry)
            } label: {
                HStack(spacing: 10) {
                    ZoneMap(layout: entry.arrangement.layout, filled: Set(entry.arrangement.activeSlots.keys))
                        .padding(3)
                        .frame(width: 44, height: 25)
                        .background(Color(red: 0.09, green: 0.13, blue: 0.19), in: .rect(cornerRadius: 5))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        let count = entry.arrangement.activeSlots.count
                        Text("\(entry.arrangement.layout.name) · \(count) \(count == 1 ? "window" : "windows")")
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryInk)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: -3) {
                        ForEach(appIDs(in: entry.arrangement), id: \.self) { appID in
                            AppIcon(appID: appID, size: 17)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Restore")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(minHeight: 37)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
            .help("Restore \(entry.name)")

            Menu {
                Button("Delete layout", role: .destructive, action: { model.delete(entry) })
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(secondaryInk)
                    .frame(width: 20, height: 25)
                    .contentShape(.rect)
            }
            .fixedSize()
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Options for \(entry.name)")
            .disabled(model.busy)
        }
        .padding(.horizontal, 7)
        .background(Color.primary.opacity(0.055), in: .rect(cornerRadius: 8))
    }

    private func appIDs(in arrangement: Arrangement) -> [String] {
        var seen: Set<String> = []
        return arrangement.activeSlots.sorted { $0.key < $1.key }
            .map(\.value.appID)
            .filter { seen.insert($0).inserted }
    }

    private func callout(_ icon: String, title: String, detail: String) -> some View {
        callout(icon, title: title, detail: detail) { EmptyView() }
    }

    private func callout<Action: View>(_ icon: String, title: String, detail: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(accent)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.12), in: .rect(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.055), in: .rect(cornerRadius: 9))
    }

    private func resultLine(_ message: AppModel.Message) -> some View {
        Label(message.text, systemImage: message.success ? "checkmark.circle.fill" : "info.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(message.success ? accent : slotInks[3])
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Menu {
                Button("Open Activity Log") { NSWorkspace.shared.open(ActivityLog.shared.fileURL) }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ActivityLog.shared.fileURL])
                }
                Button("Copy Recent Entries") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ActivityLog.shared.recentLines(), forType: .string)
                    model.showNotice("Copied recent log entries.")
                }
                Divider()
                Button("Clear Log", role: .destructive) { ActivityLog.shared.clear() }
            } label: {
                Label("Activity log", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(secondaryInk)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("See what Windows did with each window, step by step")
            Spacer()
            Button("Quit Windows") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(secondaryInk)
        }
        .font(.system(size: 10, weight: .medium))
    }
}

/// Capsule buttons with solid fills, so the main actions read clearly in both appearances.
private struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    let accent: Color
    let dark: Bool
    var height: CGFloat = 34
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let ink = prominent ? (dark ? Color(red: 0.03, green: 0.20, blue: 0.16) : .white) : Color.primary
        let fill = prominent
            ? AnyShapeStyle(LinearGradient(colors: [accent.mix(with: .white, by: dark ? 0.18 : 0.08), accent],
                                           startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(dark ? Color.white.opacity(0.09) : Color.white.opacity(0.85))
        let border = prominent ? Color.white.opacity(dark ? 0.35 : 0.18) : Color.primary.opacity(dark ? 0.16 : 0.10)

        return configuration.label
            .font(.system(size: height < 30 ? 12 : 13, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, height < 30 ? 12 : 15)
            .frame(height: height)
            .background(fill, in: .capsule)
            .overlay { Capsule().strokeBorder(border, lineWidth: 1) }
            .shadow(color: .black.opacity(prominent && isEnabled ? (dark ? 0.30 : 0.16) : 0), radius: 4, y: 2)
            .brightness(configuration.isPressed ? (dark ? 0.08 : -0.06) : 0)
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(.capsule)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ZoneMap: View {
    let layout: Layout
    var filled: Set<Int> = []
    var numbered = false
    var assignments: [Int: WindowReference] = [:]
    var monochrome: Color?

    var body: some View {
        GeometryReader { proxy in
            let zones = layout.zones
            ForEach(zones.indices, id: \.self) { index in
                tile(index, zone: zones[index], size: proxy.size)
            }
        }
    }

    private func tile(_ index: Int, zone: CGRect, size: CGSize) -> some View {
        let color = monochrome ?? zoneColors[index]
        let isFilled = filled.contains(index)
        let gutter: CGFloat = numbered ? 4 : 1.5
        let lineWidth: CGFloat = numbered ? 1 : 0.7
        let shape = RoundedRectangle(cornerRadius: numbered ? 5 : 1.2)
        let fill = shape.fill(color.opacity(isFilled ? 0.29 : 0.12))
        let outline = shape.strokeBorder(color.opacity(isFilled ? 0.83 : 0.40), lineWidth: lineWidth)
        let width = max(0, size.width * zone.width - gutter)
        let height = max(0, size.height * zone.height - gutter)

        return fill.overlay(outline)
            .overlay(alignment: .topLeading) {
                if numbered {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(7)
                }
            }
            .overlay {
                if numbered, let reference = assignments[index] {
                    ZoneLabel(reference: reference, compact: height < 60, iconOnly: height < 60 && width < 120,
                              missing: !isFilled)
                        .padding(.leading, height < 60 ? 18 : 0)
                        .padding(.horizontal, 6)
                }
            }
            .frame(width: width, height: height)
            .position(x: size.width * zone.midX, y: size.height * zone.midY)
    }
}

/// The app icon and name shown inside a zone of the monitor preview.
private struct ZoneLabel: View {
    let reference: WindowReference
    let compact: Bool
    let iconOnly: Bool
    let missing: Bool

    var body: some View {
        let stack = compact ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 5))
        stack {
            AppIcon(appID: reference.appID, size: compact ? 18 : 26)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            if !iconOnly {
                Text(reference.appName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
            }
        }
        .opacity(missing ? 0.45 : 1)
        .saturation(missing ? 0 : 1)
        .accessibilityHidden(true)
    }
}

private struct AppIcon: View {
    let appID: String
    let size: CGFloat

    var body: some View {
        Image(nsImage: AppIcons.icon(for: appID))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// Looks up and caches application icons by the identifier stored in a `WindowReference`.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for appID: String) -> NSImage {
        if let cached = cache[appID] { return cached }
        let workspace = NSWorkspace.shared
        let image: NSImage
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: appID).first,
           let icon = running.icon {
            image = icon
        } else if let url = workspace.urlForApplication(withBundleIdentifier: appID) {
            image = workspace.icon(forFile: url.path)
        } else if appID.hasPrefix("/") {
            image = workspace.icon(forFile: appID)
        } else {
            image = workspace.icon(for: .applicationBundle)
        }
        cache[appID] = image
        return image
    }
}
