import AppKit
import Combine
import SwiftUI

private let accent = Color(red: 0.50, green: 0.93, blue: 0.80)
private let secondaryInk = Color(red: 0.67, green: 0.73, blue: 0.83)
private let zoneColors: [Color] = [accent, Color(red: 0.51, green: 0.75, blue: 1),
                                   Color(red: 0.77, green: 0.67, blue: 1),
                                   Color(red: 1, green: 0.77, blue: 0.53)]

struct SnapperPanel: View {
    private enum Tab: String, CaseIterable { case arrange = "Arrange", saved = "Saved" }

    let model: SnapperModel
    @State private var tab: Tab = .arrange
    @State private var naming = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

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
        .background {
            ZStack(alignment: .topLeading) {
                Color(red: 0.049, green: 0.065, blue: 0.102)
                RadialGradient(colors: [Color(red: 0.12, green: 0.25, blue: 0.27).opacity(0.54), .clear],
                               center: .topLeading, startRadius: 12, endRadius: 360)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .onAppear { model.refresh() }
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
                Text("MacSnapper")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .accessibilityAddTraits(.isHeader)
                Text("External display layouts")
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
            .background(.white.opacity(0.06), in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("External display")
        .help(model.display?.name ?? "Choose the external display to use")
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                    naming = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item == .arrange ? "rectangle.split.2x2" : "bookmark")
                        Text(item.rawValue)
                        if item == .saved, !model.saved.isEmpty {
                            Text(model.saved.count, format: .number)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.08), in: .capsule)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tab == item ? .white : secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(tab == item ? .white.opacity(0.10) : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.30), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.07)) }
    }

    private var arrangementPanel: some View {
        VStack(spacing: 12) {
            monitorPreview

            if model.display == nil {
                callout("display", title: model.displayWasSelected ? "External display disconnected" : "Choose your external display",
                        detail: "Connect your monitor in extended mode to arrange windows on it.")
            } else if !model.trusted {
                callout("lock.shield", title: "Allow window control", detail: "Enable MacSnapper in Accessibility so it can move and resize windows.") {
                    Button("Open Accessibility Settings", action: model.openAccessibility)
                        .buttonStyle(PanelButtonStyle(prominent: true))
                }
            } else {
                layoutPicker
                windowSlots
                if naming { saveForm }
                if let message = model.message { resultLine(message) }
                actionBar
            }
        }
    }

    private var monitorPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(model.display?.name ?? "Ultrawide display", systemImage: "display")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(model.display?.resolution ?? "5120 × 1440")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryInk)
            }

            VStack(spacing: 0) {
                ZoneMap(layout: model.arrangement.layout, filled: Set(model.matches.keys), numbered: true)
                    .padding(6)
                    .frame(height: 95)
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

    private var layoutPicker: some View {
        HStack(spacing: 6) {
            ForEach(Layout.allCases) { layout in
                let selected = model.arrangement.layout == layout
                Button {
                    model.select(layout)
                } label: {
                    HStack(spacing: 7) {
                        ZoneMap(layout: layout, monochrome: selected ? accent : secondaryInk)
                            .frame(width: 25, height: 13)
                            .accessibilityHidden(true)
                        Text(layout.name)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected ? accent : secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 33)
                    .background(selected ? accent.opacity(0.10) : .white.opacity(0.045), in: .rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? accent.opacity(0.32) : .white.opacity(0.08)) }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
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
                Text("\(model.matches.count)/4")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryInk)
                    .accessibilityLabel("\(model.matches.count) of 4 windows available")
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

            ForEach(0..<4) { slot in slotMenu(slot) }

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
                    .foregroundStyle(zoneColors[slot])
                    .frame(width: 20, height: 20)
                    .background(zoneColors[slot].opacity(0.12), in: .rect(cornerRadius: 5))
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(reference == nil ? secondaryInk : .white)
                Spacer(minLength: 2)
                if let reference {
                    Text(live == nil ? "Missing" : reference.appName)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .frame(maxWidth: 102, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(live == nil ? zoneColors[3] : secondaryInk)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(secondaryInk)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .frame(height: 29)
            .background(.white.opacity(0.045), in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
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
            .buttonStyle(PanelButtonStyle())
            .disabled(model.arrangement.slots.isEmpty || model.busy)

            Button(action: model.snap) {
                let count = model.arrangement.slots.count
                HStack(spacing: 6) {
                    if model.busy {
                        ProgressView().controlSize(.small).scaleEffect(0.65).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                    Text(count == 0 ? "Snap windows" : count == 1 ? "Snap 1 window" : "Snap \(count) windows")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .disabled(!model.canSnap)
        }
    }

    private var saveForm: some View {
        HStack(spacing: 7) {
            TextField("Arrangement name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
            Button(model.hasSavedLayout(named: name) ? "Update" : "Save", action: save)
                .buttonStyle(PanelButtonStyle(prominent: true))
                .disabled(!canSaveName)
        }
    }

    private var canSaveName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy
            && !model.arrangement.slots.isEmpty
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
                        .buttonStyle(PanelButtonStyle(prominent: true))
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
                    ZoneMap(layout: entry.arrangement.layout, filled: Set(entry.arrangement.slots.keys))
                        .padding(3)
                        .frame(width: 44, height: 25)
                        .background(.black.opacity(0.4), in: .rect(cornerRadius: 5))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        let count = entry.arrangement.slots.count
                        Text("\(entry.arrangement.layout.name) · \(count) \(count == 1 ? "window" : "windows")")
                            .font(.system(size: 10))
                            .foregroundStyle(secondaryInk)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.left")
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
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Options for \(entry.name)")
            .disabled(model.busy)
        }
        .padding(.horizontal, 7)
        .background(.white.opacity(0.055), in: .rect(cornerRadius: 8))
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
        .background(.white.opacity(0.055), in: .rect(cornerRadius: 9))
    }

    private func resultLine(_ message: SnapperModel.Message) -> some View {
        Label(message.text, systemImage: message.success ? "checkmark.circle.fill" : "info.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(message.success ? accent : zoneColors[3])
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Label("External display only", systemImage: "display")
                .foregroundStyle(secondaryInk)
            Spacer()
            Button("Quit MacSnapper") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(secondaryInk)
        }
        .font(.system(size: 10, weight: .medium))
    }
}

private struct ZoneMap: View {
    let layout: Layout
    var filled: Set<Int> = []
    var numbered = false
    var monochrome: Color?

    var body: some View {
        GeometryReader { proxy in
            let gutter: CGFloat = numbered ? 4 : 1.5
            let corner: CGFloat = numbered ? 5 : 1.2
            ForEach(Array(layout.zones.enumerated()), id: \.offset) { index, zone in
                let color = monochrome ?? zoneColors[index]
                let tile = RoundedRectangle(cornerRadius: corner)
                let isFilled = filled.contains(index)
                tile.fill(color.opacity(isFilled ? 0.29 : 0.12))
                    .overlay { tile.strokeBorder(color.opacity(isFilled ? 0.83 : 0.40), lineWidth: numbered ? 1 : 0.7) }
                    .overlay(alignment: .topLeading) {
                        if numbered {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(color)
                                .padding(7)
                        }
                    }
                    .frame(width: max(0, proxy.size.width * zone.width - gutter),
                           height: max(0, proxy.size.height * zone.height - gutter))
                    .position(x: proxy.size.width * zone.midX, y: proxy.size.height * zone.midY)
            }
        }
    }
}

private struct PanelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let background = prominent ? accent : .white.opacity(0.065)
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color(red: 0.04, green: 0.16, blue: 0.14) : .white)
            .padding(.horizontal, 11)
            .frame(minHeight: 33)
            .background(background.opacity(configuration.isPressed ? 0.76 : 1), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(prominent ? 0.15 : 0.09)) }
            .opacity(enabled ? 1 : 0.38)
            .contentShape(.rect)
    }
}
