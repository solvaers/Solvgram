import Foundation
import AVFoundation
import OpusBinding
import AudioWaveform

// MARK: Solvgram — Send Video as Voice: the sound of a recorded round video, encoded the way the
// voice recorder encodes (ManagedAudioRecorder): 48 kHz mono 16-bit PCM, 20 ms Opus packets in
// Ogg, with the same 100-sample, 5-bit waveform.
public struct SolvgramEncodedVoice {
    public let data: Data
    public let duration: Double
    public let waveform: Data?
}

func solvgramEncodeVoice(asset: AVAsset, timeRange: CMTimeRange?) -> SolvgramEncodedVoice? {
    guard let track = asset.tracks(withMediaType: .audio).first, let reader = try? AVAssetReader(asset: asset) else {
        return nil
    }
    if let timeRange {
        reader.timeRange = timeRange
    }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ])
    guard reader.canAdd(output) else {
        return nil
    }
    reader.add(output)
    guard reader.startReading() else {
        return nil
    }
    defer { if reader.status == .reading { reader.cancelReading() } }

    let dataItem = TGDataItem()
    let writer = TGOggOpusWriter()
    guard writer.begin(with: dataItem) else {
        return nil
    }

    let packetSize = 960 * 2
    var pending = Data()
    var peaks: [Int16] = []

    func writePacket(_ packet: inout Data) -> Bool {
        return packet.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            var peak: Int16 = 0
            for sample in samples {
                let magnitude = sample == Int16.min ? Int16.max : abs(sample)
                if magnitude > peak {
                    peak = magnitude
                }
            }
            peaks.append(peak)
            return writer.writeFrame(raw.baseAddress!.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(raw.count))
        }
    }

    while let sampleBuffer = output.copyNextSampleBuffer() {
        if let block = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var chunk = Data(count: length)
            let status = chunk.withUnsafeMutableBytes { raw in
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { return nil }
            pending.append(chunk)
        }
        var offset = 0
        while pending.count - offset >= packetSize {
            var packet = pending.subdata(in: offset ..< offset + packetSize)
            guard writePacket(&packet) else { return nil }
            offset += packetSize
        }
        if offset != 0 {
            pending = pending.subdata(in: offset ..< pending.count)
        }
    }
    if !pending.isEmpty {
        var packet = pending
        packet.append(Data(count: packetSize - pending.count))
        guard writePacket(&packet) else { return nil }
    }

    guard reader.status == .completed, writer.writeFrame(nil, frameByteCount: 0), writer.encodedDuration() >= 0.5 else {
        return nil
    }
    return SolvgramEncodedVoice(data: dataItem.data(), duration: writer.encodedDuration(), waveform: solvgramWaveform(peaks: peaks))
}

/// Encodes 48 kHz mono 16-bit samples as a voice message (Opus in Ogg, with its waveform).
public func solvgramEncodeVoiceMessage(samples: [Int16]) -> SolvgramEncodedVoice? {
    let dataItem = TGDataItem()
    let writer = TGOggOpusWriter()
    guard !samples.isEmpty, writer.begin(with: dataItem) else {
        return nil
    }
    let packetLength = 960
    var peaks: [Int16] = []
    var packet = [Int16](repeating: 0, count: packetLength)
    var offset = 0
    while offset < samples.count {
        let count = min(packetLength, samples.count - offset)
        var peak: Int16 = 0
        for i in 0 ..< packetLength {
            let sample: Int16 = i < count ? samples[offset + i] : 0
            packet[i] = sample
            let magnitude = sample == Int16.min ? Int16.max : abs(sample)
            if magnitude > peak {
                peak = magnitude
            }
        }
        peaks.append(peak)
        let written = packet.withUnsafeMutableBytes { raw in
            writer.writeFrame(raw.baseAddress!.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(raw.count))
        }
        guard written else { return nil }
        offset += packetLength
    }
    guard writer.writeFrame(nil, frameByteCount: 0) else {
        return nil
    }
    return SolvgramEncodedVoice(data: dataItem.data(), duration: writer.encodedDuration(), waveform: solvgramWaveform(peaks: peaks))
}

private func solvgramWaveform(peaks: [Int16]) -> Data? {
    guard !peaks.isEmpty else {
        return nil
    }
    var scaled = [Int16](repeating: 0, count: 100)
    for (i, sample) in peaks.enumerated() {
        let index = i * 100 / peaks.count
        if scaled[index] < sample {
            scaled[index] = sample
        }
    }
    let sum = scaled.reduce(Int64(0)) { $0 + Int64($1) }
    let calculatedPeak = max(Int64(2500), Int64(Double(sum) * 1.8 / 100.0))
    for i in 0 ..< 100 {
        scaled[i] = Int16(clamping: min(31, min(Int64(scaled[i]), calculatedPeak) * 31 / calculatedPeak))
    }
    let samples = scaled.withUnsafeBufferPointer { Data(buffer: $0) }
    let bitstream = AudioWaveform(samples: samples, peak: 31).makeBitstream()
    return AudioWaveform(bitstream: bitstream, bitsPerSample: 5).makeBitstream()
}
