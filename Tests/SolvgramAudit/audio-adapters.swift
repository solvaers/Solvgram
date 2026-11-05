import Foundation
import AVFoundation

// Codec boundary only: deterministic writer failures exercise the production
// packet loops. Waveform packing and AVAudioEngine rendering are real sources.
final class TGDataItem {
    var bytes = Data()
    func data() -> Data { self.bytes }
}
final class TGOggOpusWriter {
    static var failPacket: Int?
    static var failFinal = false
    static var last: TGOggOpusWriter?
    var packets: [Data] = []
    var finalized = false
    private var item: TGDataItem?
    func begin(with item: TGDataItem) -> Bool {
        self.item = item; Self.last = self; return true
    }
    func writeFrame(_ bytes: UnsafePointer<UInt8>?, frameByteCount: UInt) -> Bool {
        guard let bytes else { self.finalized = true; return !Self.failFinal }
        self.packets.append(Data(bytes:bytes,count:Int(frameByteCount)))
        if self.packets.count == Self.failPacket { return false }
        self.item?.bytes.append(contentsOf:[0x4f,0x67,0x67])
        return true
    }
    func encodedDuration() -> Double { Double(self.packets.count) * 0.02 }
}
final class OggOpusReader {
    init?(path: String) { return nil }
    func read(_ bytes: UnsafeMutableRawPointer, bufSize: Int32) -> Int32 { 0 }
}
