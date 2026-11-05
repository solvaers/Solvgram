func checkAudio(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(),message)
}

TGOggOpusWriter.failPacket = nil
let partial = solvgramEncodeVoiceMessage(samples:[Int16](repeating:Int16.min,count:961))
checkAudio(partial != nil,"A partial final packet is encoded")
checkAudio(TGOggOpusWriter.last!.packets.map(\.count) == [1920,1920],"Opus receives full 20 ms packets")
let lastPacket = TGOggOpusWriter.last!.packets.last!
checkAudio(lastPacket.dropFirst(2).allSatisfy { $0 == 0 },"Only the missing tail is zero-padded")
checkAudio(partial?.waveform?.count == 63,"The actual waveform encoder packs 100 five-bit samples")
checkAudio(TGOggOpusWriter.last!.finalized,"A successful stream is finalized")
TGOggOpusWriter.failPacket = 2
checkAudio(solvgramEncodeVoiceMessage(samples:[Int16](repeating:10,count:4000)) == nil,"A packet failure cannot return a corrupt voice message")
checkAudio(TGOggOpusWriter.last!.packets.count == 2 && !TGOggOpusWriter.last!.finalized,"Encoding stops at its first failed packet")
TGOggOpusWriter.failPacket = nil; TGOggOpusWriter.failFinal = true
checkAudio(solvgramEncodeVoiceMessage(samples:[1,2,3]) == nil,"A finalization failure is propagated")
checkAudio(solvgramEncodeVoiceMessage(samples:[]) == nil,"Empty samples are rejected")
TGOggOpusWriter.failFinal = false

let count = 48_000
let source = (0..<count).map { Int16(sin(Double($0) * 2 * .pi * 440 / 48_000) * 10_000) }
var checked = 0
for name in ["high","cartoon","low","robot"] {
    for level in [1,3,5] {
        let effect = solvgramVoiceEffect(name,level:level)!
        let output = solvgramRender(source,effect:effect)
        checkAudio(output != nil,"AVAudioEngine renders \(name) level \(level)")
        checkAudio(output!.count == Int(Double(count) / Double(effect.rate)),"Rendering retains the full expected duration")
        checkAudio(output!.contains { abs(Int($0)) > 50 },"The effect produces an audible signal")
        checked += 1
    }
}
print("AUDIO_AUDIT_OK packetFailures=2 nativeEffects=\(checked)")

for rate: Float in [0.45, 0.6, 0.75, 0.9, 1.05] {
    var effect = solvgramVoiceEffect("high",level:3)!
    effect.rate *= rate
    let output = solvgramRender(source,effect:effect)
    checkAudio(output != nil && output!.count == Int(Double(count) / Double(effect.rate)),"Speed renders the complete adjusted duration")
}
print("VOICE_SPEED_AUDIO_OK rates=5")
