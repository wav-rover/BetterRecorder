//
//  BetterRecorderApp.swift
//  BetterRecorder
//
//  Created by Jeremy Deveney on 22/03/2026.
//

import CoreGraphics
import SwiftUI

@main
struct BetterRecorderApp: App {
    private static let shellCoordinator = AppShellCoordinator()

    @State private var launchCapture = LaunchCaptureController(coordinator: BetterRecorderApp.shellCoordinator)

    init() {
        _ = CGMainDisplayID()
    }

    var body: some Scene {
        WindowGroup(id: AppWindowID.hudOverlay.rawValue) {
            LaunchHUDView(launch: launchCapture)
                .windowSceneBridge(coordinator: Self.shellCoordinator)
                .onAppear {
                    launchCapture.loadPersistedDefaults()
                }
        }
        .defaultLaunchBehavior(.automatic)
        .defaultSize(width: 560, height: 320)
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        WindowGroup(id: AppWindowID.editor.rawValue) {
            EditorSceneHost(launchCapture: launchCapture)
                .windowSceneBridge(coordinator: Self.shellCoordinator)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))

        WindowGroup(id: AppWindowID.sourceSelector.rawValue) {
            SourceSelectorView(launch: launchCapture)
                .windowSceneBridge(coordinator: Self.shellCoordinator)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 620, height: 420)
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        WindowGroup(id: AppWindowID.countdown.rawValue) {
            CountdownOverlayView(launch: launchCapture)
                .windowSceneBridge(coordinator: Self.shellCoordinator)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        MenuBarExtra("BetterRecorder", systemImage: "record.circle") {
            TrayMenuContent(launch: launchCapture)
        }
    }
}

private struct TrayMenuContent: View {
    @Bindable var launch: LaunchCaptureController

    var body: some View {
        Button("Show HUD") {
            launch.showHudWindow()
        }
        Divider()
        Button("Stop recording") {
            Task { await launch.stopRecordingFromTray() }
        }
        .disabled(!launch.recording)
    }
}

private struct EditorSceneHost: View {
    @Bindable var launchCapture: LaunchCaptureController

    var body: some View {
        EditorPlaceholderRoot(
            mainVideoPath: launchCapture.pendingMainVideoURL?.path,
            webcamPath: launchCapture.pendingWebcamVideoURL?.path
        )
    }
}
