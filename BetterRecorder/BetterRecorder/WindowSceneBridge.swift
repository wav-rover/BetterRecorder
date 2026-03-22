//
//  WindowSceneBridge.swift
//  BetterRecorder
//
//  Captures `openWindow` / `dismissWindow` into `AppShellCoordinator` once the scene is active.
//

import SwiftUI

struct WindowSceneBridge: ViewModifier {
    let coordinator: AppShellCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                coordinator.attachWindowActions(open: openWindow, dismiss: dismissWindow)
            }
    }
}

extension View {
    func windowSceneBridge(coordinator: AppShellCoordinator) -> some View {
        modifier(WindowSceneBridge(coordinator: coordinator))
    }
}
