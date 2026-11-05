import Foundation
import AVFoundation
import AccountContext
import OpusBinding
import SGSimpleSettings
import VideoMessageCameraScreen

// MARK: Solvgram — Voice Changer: a recorded voice message, decoded, run through the chosen effect
// at its strength (1...5) and encoded again, before it is previewed or sent. Applied in
// ManagedAudioRecorder.takeData(), which both the instant send and the preview read.

private struct SolvgramVoiceEffect {
    /// Cents, -2400...2400.
    var pitch: Float
    /// Playback speed; above 1 the message gets shorter.
    var rate: Float = 1.0
    /// Robot: ring modulation, Hz, and how much of it is mixed in.
    var ringFrequency: Float? = nil
    var ringMix: Float = 0.0
    /// Robot: a short feedback delay that gives a metallic ring.
    var metallicFeedback: Float = 0.0
}

// Level 1 is already clearly audible: each level is what the one above it used to be, and 5 goes past the old maximum.
private func solvgramVoiceEffect(_ name: String, level: Int) -> SolvgramVoiceEffect? {
    let i = min(4, max(0, level - 1))
    switch name {
    case "high":
        return SolvgramVoiceEffect(pitch: [500.0, 700.0, 900.0, 1100.0, 1400.0][i])
    case "cartoon":
        return SolvgramVoiceEffect(pitch: [600.0, 800.0, 1000.0, 1200.0, 1500.0][i], rate: [1.1, 1.15, 1.2, 1.25, 1.35][i])
    case "low":
        return SolvgramVoiceEffect(pitch: [-500.0, -700.0, -900.0, -1100.0, -1400.0][i])
    case "robot":
        return SolvgramVoiceEffect(
            pitch: [-150.0, -200.0, -250.0, -300.0, -350.0][i],
            ringFrequency: [55.0, 70.0, 85.0, 100.0, 115.0][i],
            ringMix: [0.6, 0.7, 0.8, 0.9, 1.0][i],
            metallicFeedback: [0.3, 0.35, 0.4, 0.45, 0.5][i]
        )
    default:
        return nil
    }
}

/// 48 kHz mono samples of an Ogg Opus voice message.
private func solvgramDecodeVoice(_ data: Data) -> [Int16]? {
    let path = NSTemporaryDirectory() + "solvgram-voice-\(UUID().uuidString).ogg"
    guard (try? data.write(to: URL(fileURLWithPath: path))) != nil else {
        return nil
    }
    defer {
        try? FileManager.default.removeItem(atPath: path)
    }
    guard let reader = OggOpusReader(path: path) else {
        return nil
    }
    var samples: [Int16] = []
    var buffer = [Int16](repeating: 0, count: 5760)
    while true {
        let count = buffer.withUnsafeMutableBytes { raw -> Int32 in
            return reader.read(raw.baseAddress!, bufSize: Int32(raw.count / 2))
        }
        if count <= 0 {
            break
        }
        samples.append(contentsOf: buffer[0 ..< Int(count)])
    }
    return samples.isEmpty ? nil : samples
}

private func solvgramRender(_ samples: [Int16], effect: SolvgramVoiceEffect) -> [Int16]? {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 1), let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let inputChannel = input.floatChannelData?[0] else {
        return nil
    }
    for i in 0 ..< samples.count {
        inputChannel[i] = Float(samples[i]) / 32768.0
    }
    input.frameLength = AVAudioFrameCount(samples.count)

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    timePitch.pitch = effect.pitch
    timePitch.rate = effect.rate
    engine.attach(player)
    engine.attach(timePitch)
    engine.connect(player, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)

    let maximumFrameCount: AVAudioFrameCount = 4096
    do {
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
        try engine.start()
    } catch {
        return nil
    }
    player.scheduleBuffer(input, completionHandler: nil)
    player.play()
    defer {
        player.stop()
        engine.stop()
    }

    guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maximumFrameCount) else {
        return nil
    }
    let expectedCount = Int(Double(samples.count) / Double(effect.rate))
    var rendered: [Float] = []
    rendered.reserveCapacity(expectedCount)
    var stalled = 0
    while rendered.count < expectedCount {
        let frames = AVAudioFrameCount(min(Int(maximumFrameCount), expectedCount - rendered.count))
        guard let status = try? engine.renderOffline(frames, to: output) else {
            return nil
        }
        switch status {
        case .success:
            guard output.frameLength > 0, let channel = output.floatChannelData?[0] else { return nil }
            rendered.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            stalled = 0
        case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
            stalled += 1
            // Repeated non-progress must fail, not spin for thousands of calls
            // or return a truncated recording as if conversion succeeded.
            guard stalled < 64 else { return nil }
            continue
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }

    if let ringFrequency = effect.ringFrequency {
        // Ring modulation for the robotic buzz, then a short feedback delay for the metallic ring.
        let phaseStep = 2.0 * Float.pi * ringFrequency / 48000.0
        for i in 0 ..< rendered.count {
            let modulated = rendered[i] * sin(phaseStep * Float(i))
            rendered[i] = rendered[i] * (1.0 - effect.ringMix) + modulated * effect.ringMix * 1.6
        }
        let delay = 48 * 7
        if rendered.count > delay {
            for i in delay ..< rendered.count {
                rendered[i] += rendered[i - delay] * effect.metallicFeedback
            }
        }
    }

    var peak: Float = 0.0
    for value in rendered {
        peak = max(peak, abs(value))
    }
    let gain: Float = peak > 0.98 ? 0.98 / peak : 1.0
    return rendered.map { Int16(max(-32768.0, min(32767.0, $0 * gain * 32767.0))) }
}

/// The recorded message with the Voice Changer's effect, or unchanged when it is off or fails.
func solvgramApplyVoiceEffect(_ data: RecordedAudioData) -> RecordedAudioData {
    let name = SolvgramSettings.voiceEffect
    guard var effect = solvgramVoiceEffect(name, level: SolvgramSettings.voiceEffectLevel(name)) else {
        return data
    }
    effect.rate *= SolvgramSettings.voiceSpeed
    guard let samples = solvgramDecodeVoice(data.compressedData), let processed = solvgramRender(samples, effect: effect), let encoded = solvgramEncodeVoiceMessage(samples: processed) else {
        return data
    }
    return RecordedAudioData(compressedData: encoded.data, resumeData: data.resumeData, duration: encoded.duration, waveform: encoded.waveform, trimRange: effect.rate == 1.0 ? data.trimRange : nil)
}
