"""Compile actual packet/waveform/DSP code with an injectable codec boundary."""
from pathlib import Path
import re, subprocess
root=Path(__file__).resolve().parents[2]
stage=Path('/tmp/solvgram-audit-100023/audio');stage.mkdir(parents=True,exist_ok=True)
voice=(root/'submodules/TelegramUI/Sources/SolvgramVoiceChanger.swift').read_text()
voice=voice[:voice.index('/// The recorded message')]
encoder=(root/'submodules/TelegramUI/Components/VideoMessageCameraScreen/Sources/SolvgramVideoToVoice.swift').read_text()
def adapt(s):
    return re.sub(r'^import (?!Foundation$|AVFoundation$).+\n','',s,flags=re.M)
(stage/'main.swift').write_text((Path(__file__).parent/'audio-adapters.swift').read_text()+'\n'+adapt(voice)+'\n'+adapt(encoder)+'\n'+(Path(__file__).parent/'audio-checks.swift').read_text())
subprocess.run(['swiftc','-swift-version','5','-O','-module-cache-path','/tmp/solvgram-audit-swift-cache',str(stage/'main.swift'),str(root/'submodules/AudioWaveform/Sources/AudioWaveform.swift'),'-framework','AVFoundation','-o',str(stage/'audio-audit')],check=True)
subprocess.run([str(stage/'audio-audit')],check=True)
