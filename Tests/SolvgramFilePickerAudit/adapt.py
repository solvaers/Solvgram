from pathlib import Path
import re,sys,plistlib,shutil
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);app=out/'FilePickerAudit.app';app.mkdir(parents=True,exist_ok=True)
def stripped(text):return re.sub(r'^import (?!Foundation$|UIKit$|AVFoundation$|UniformTypeIdentifiers$).+\n','',text,flags=re.M)
parts=[(Path(__file__).parent/'adapters.swift').read_text()]
# Use real signal cancellation and delivery; omit only an unrelated async extension requiring take().
parts += [(root/'submodules/SSignalKit/SwiftSignalKit/Source'/name).read_text() for name in ['Atomic.swift','Disposable.swift','Subscriber.swift']]
parts += [(root/'submodules/SSignalKit/SwiftSignalKit/Source/Signal.swift').read_text().split('@available(iOS 13.0, macOS 10.15, *)')[0]]
parts += [stripped((root/path).read_text()) for path in ['submodules/ICloudResources/Sources/ICloudResources.swift','submodules/LegacyMediaPickerUI/Sources/LegacyICloudFilePicker.swift']]
parts += [(Path(__file__).parent/'profile-audit.swift').read_text(), (Path(__file__).parent/'audit.swift').read_text()]
(out/'main.swift').write_text('\n'.join(parts))
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'app.solvgram.file-picker-audit','CFBundleExecutable':'FilePickerAudit','CFBundleName':'FilePickerAudit','CFBundleVersion':'100029','CFBundleShortVersionString':'1.0','CFBundlePackageType':'APPL','MinimumOSVersion':'17.0','LSRequiresIPhoneOS':True,'UILaunchScreen':{},'UIDeviceFamily':[1]}))

assets=out/'AuditIcons.xcassets';assets.mkdir(exist_ok=True)
shutil.copytree(root/'submodules/TelegramUI/Images.xcassets/Chat/Context Menu/MarkAsRead.imageset',assets/'MarkAsRead.imageset',dirs_exist_ok=True)
