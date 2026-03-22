//
//  SourceSelectorView.swift
//  BetterRecorder
//
//  Screen / window picker (Electron SourceSelector parity — English UI).
//

import ScreenCaptureKit
import SwiftUI

struct SourceSelectorView: View {
    @Bindable var launch: LaunchCaptureController

    @State private var content: SCShareableContent?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var tab: Tab = .screens
    @State private var selectedDisplay: SCDisplay?
    @State private var selectedWindow: SCWindow?

    private enum Tab: String, CaseIterable {
        case screens = "Screens"
        case windows = "Windows"
    }

    private var ownBundleID: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading sources…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView {
                    if tab == .screens {
                        screenGrid
                    } else {
                        windowGrid
                    }
                }
                .padding(12)

                HStack {
                    Button("Cancel") {
                        launch.cancelSourceSelector()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Share") {
                        confirmSelection()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canShare)
                }
                .padding(12)
                .background(.bar)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background {
            TransparentWindowConfigurator(windowIdentifier: AppWindowID.sourceSelector.rawValue)
        }
        .task {
            await loadSources()
        }
    }

    private var canShare: Bool {
        switch tab {
        case .screens:
            return selectedDisplay != nil
        case .windows:
            return selectedWindow != nil && !isBlockedWindow(selectedWindow!)
        }
    }

    private var screenGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
            ForEach(content?.displays ?? [], id: \.displayID) { display in
                let name = "Display \(display.displayID)"
                Button {
                    selectedDisplay = display
                    selectedWindow = nil
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay {
                                Image(systemName: "display")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        Text(name)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedDisplay?.displayID == display.displayID ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var windowGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Some windows may be unavailable for capture.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                ForEach(content?.windows ?? [], id: \.windowID) { window in
                    let blocked = isBlockedWindow(window)
                    Button {
                        guard !blocked else { return }
                        selectedWindow = window
                        selectedDisplay = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.quaternary)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "macwindow")
                                        .font(.largeTitle)
                                        .foregroundStyle(blocked ? .tertiary : .secondary)
                                }
                            Text(Self.displayTitle(for: window))
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(blocked ? .tertiary : .primary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedWindow?.windowID == window.windowID ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(blocked)
                }
            }
        }
    }

    private static func displayTitle(for window: SCWindow) -> String {
        let t = window.title ?? ""
        return t.isEmpty ? "Window \(window.windowID)" : t
    }

    private func isBlockedWindow(_ window: SCWindow) -> Bool {
        guard let bid = window.owningApplication?.bundleIdentifier else { return false }
        return bid == ownBundleID
    }

    private func loadSources() async {
        isLoading = true
        loadError = nil
        do {
            let c = try await ShareableContentService.fetchContent()
            content = c
            if c.displays.isEmpty, !c.windows.isEmpty {
                tab = .windows
            } else if !c.displays.isEmpty, c.windows.isEmpty {
                tab = .screens
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func confirmSelection() {
        if tab == .screens, let d = selectedDisplay {
            let name = "Display \(d.displayID)"
            let source = CaptureSource.screen(display: d, name: name)
            launch.applySelectedSource(source)
            return
        }

        if tab == .windows, let w = selectedWindow, !isBlockedWindow(w) {
            let source = CaptureSource.window(w, displayName: Self.displayTitle(for: w))
            launch.applySelectedSource(source)
        }
    }
}
