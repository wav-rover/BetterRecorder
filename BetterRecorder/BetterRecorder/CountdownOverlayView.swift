//
//  CountdownOverlayView.swift
//  BetterRecorder
//
//  Full-window countdown (Electron CountdownOverlay parity — click or Escape cancels).
//

import AppKit
import SwiftUI

struct CountdownOverlayView: View {
    @Bindable var launch: LaunchCaptureController

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    launch.cancelCountdownFromUser()
                }

            if let tick = launch.countdownTick {
                Text("\(tick)")
                    .font(.system(size: 100, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.2), radius: 30)
                    .padding(40)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            TransparentWindowConfigurator(windowIdentifier: AppWindowID.countdown.rawValue)
            FullScreenBorderlessWindowConfigurator()
        }
        .onExitCommand {
            launch.cancelCountdownFromUser()
        }
    }
}

/// Expands the countdown `WindowGroup` to the main screen frame (Electron full-screen overlay feel).
private struct FullScreenBorderlessWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async {
            guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
            let frame = screen.frame
            window.setFrame(frame, display: true)
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
