//
//  ShellPlaceholderViews.swift
//  BetterRecorder
//
//  Editor placeholder until later migration steps.
//

import SwiftUI

struct EditorPlaceholderRoot: View {
    var mainVideoPath: String?
    var webcamPath: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("BetterRecorder Editor")
                .font(.title2.weight(.semibold))
            Text("Preview, timeline, and export will land in later migration steps.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let mainVideoPath {
                Text("Main video: \(mainVideoPath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let webcamPath {
                Text("Webcam: \(webcamPath)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color.black)
        .foregroundStyle(.white)
    }
}
