//
//  LaunchHUDView.swift
//  BetterRecorder
//
//  HUD capture bar (Electron LaunchWindow parity — English UI).
//

import SwiftUI

struct LaunchHUDView: View {
    @Bindable var launch: LaunchCaptureController
    private static let countdownChoices = [0, 3, 5, 10]

    var body: some View {
        // Fixed-height layout: the control bar stays anchored to the bottom of the window.
        // Dropdowns open in the space above the bar (spacer shrinks) so the window does not resize
        // and the bar does not jump when a menu opens.
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            if launch.activeDropdown != .none {
                dropdownCard
            }

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                if launch.recording {
                    recordingBar
                } else {
                    idleBar
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .frame(minWidth: 520)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .bottom)
        .background {
            TransparentWindowConfigurator(windowIdentifier: AppWindowID.hudOverlay.rawValue)
        }
    }

    private var idleBar: some View {
        HStack(spacing: 6) {
            Button {
                launch.activeDropdown = launch.activeDropdown == .sources ? .none : .sources
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "display")
                    Text(launch.hasSelectedSource ? (launch.selectedSource?.displayName ?? "Display") : "Choose source")
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .rotationEffect(.degrees(launch.activeDropdown == .sources ? 0 : 180))
                }
            }
            .buttonStyle(.plain)

            divider

            micToggle
            webcamToggle
            countdownMenuButton

            divider

            Button {
                Task { await launch.toggleRecording() }
            } label: {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .disabled(launch.countdownActive)
            .help("Start recording")

            divider

            moreMenu
            hideButton
            closeButton
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(launch.paused ? Color.yellow : Color.red)
                    .frame(width: 7, height: 7)
                Text(launch.paused ? "PAUSED" : "REC")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(launch.paused ? .yellow : .red)
            }

            Text(launch.elapsedTimeString)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .frame(minWidth: 52)

            divider

            Image(systemName: launch.microphoneEnabled ? "mic.fill" : "mic.slash")
                .foregroundStyle(launch.microphoneEnabled ? .primary : .secondary)

            divider

            Button {
                launch.pauseOrResume()
            } label: {
                Image(systemName: launch.paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            .help(launch.paused ? "Resume" : "Pause")

            Button {
                Task { await launch.toggleRecording() }
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Stop")

            Button {
                launch.hideHudWindow()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .help("Hide HUD")

            Button {
                Task { await launch.cancelRecording() }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Cancel recording")
        }
    }

    private var micToggle: some View {
        Button {
            launch.activeDropdown = launch.activeDropdown == .mic ? .none : .mic
        } label: {
            Image(systemName: launch.microphoneEnabled ? "mic.fill" : "mic.slash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(launch.microphoneEnabled ? .blue : .secondary)
        .disabled(launch.recording)
        .help("Microphone")
    }

    private var webcamToggle: some View {
        Button {
            launch.activeDropdown = launch.activeDropdown == .webcam ? .none : .webcam
        } label: {
            Image(systemName: launch.webcamEnabled ? "video.fill" : "video.slash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(launch.webcamEnabled ? .blue : .secondary)
        .disabled(launch.recording)
        .help("Webcam")
    }

    private var countdownMenuButton: some View {
        Button {
            launch.activeDropdown = launch.activeDropdown == .countdown ? .none : .countdown
        } label: {
            Image(systemName: "timer")
        }
        .buttonStyle(.plain)
        .foregroundStyle(launch.countdownDelaySeconds > 0 ? .blue : .secondary)
        .disabled(launch.recording)
        .help("Countdown delay")
    }

    private var moreMenu: some View {
        Menu {
            Toggle("Hide HUD from capture", isOn: $launch.hideHudFromCapture)
            Button("Recordings folder…") {
                launch.chooseRecordingsFolder()
            }
            Button("Open video…") {
                Task { await launch.openVideoFileThenEditor() }
            }
            Button("Open project…") {
                Task { await launch.openProjectFileThenEditor() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("More")
    }

    private var hideButton: some View {
        Button {
            launch.hideHudWindow()
        } label: {
            Image(systemName: "minus")
        }
        .buttonStyle(.plain)
        .help("Hide HUD")
    }

    private var closeButton: some View {
        Button {
            launch.closeApplication()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .help("Quit")
    }

    private var divider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.35))
            .frame(width: 1, height: 18)
    }

    @ViewBuilder
    private var dropdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch launch.activeDropdown {
            case .sources:
                sourceDropdownHint
            case .mic:
                micDropdown
            case .webcam:
                webcamDropdown
            case .countdown:
                countdownDropdown
            case .more, .none:
                EmptyView()
            }
        }
        .padding(10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sourceDropdownHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen or window")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button("Open source selector…") {
                launch.openSourceSelectorWindow()
                launch.activeDropdown = .none
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var micDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Microphone")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Toggle("System audio", isOn: $launch.systemAudioEnabled)
                .disabled(launch.recording)
            Divider()
            Toggle("Enable microphone", isOn: $launch.microphoneEnabled)
                .disabled(launch.recording)
            ForEach(CaptureDeviceLists.microphoneDevices(), id: \.id) { dev in
                Button {
                    launch.microphoneDeviceID = dev.id
                    launch.microphoneEnabled = true
                } label: {
                    HStack {
                        Text(dev.name)
                        Spacer()
                        if launch.microphoneDeviceID == dev.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var webcamDropdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Webcam")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Toggle("Enable webcam", isOn: $launch.webcamEnabled)
                .disabled(launch.recording)
            ForEach(CaptureDeviceLists.webcamDevices(), id: \.id) { dev in
                Button {
                    launch.webcamDeviceID = dev.id
                    launch.webcamEnabled = true
                } label: {
                    HStack {
                        Text(dev.name)
                        Spacer()
                        if launch.webcamDeviceID == dev.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var countdownDropdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Countdown")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Self.countdownChoices, id: \.self) { sec in
                Button {
                    launch.setCountdownDelay(sec)
                    launch.activeDropdown = .none
                } label: {
                    HStack {
                        Text(sec == 0 ? "No delay" : "\(sec)s")
                        Spacer()
                        if launch.countdownDelaySeconds == sec {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
