//
//  CaptureDeviceLists.swift
//  BetterRecorder
//

import AVFoundation
import Foundation

enum CaptureDeviceLists {
    static func microphoneDevices() -> [(id: String, name: String)] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.map { ($0.uniqueID, $0.localizedName) }
    }

    static func webcamDevices() -> [(id: String, name: String)] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices.map { ($0.uniqueID, $0.localizedName) }
    }
}
