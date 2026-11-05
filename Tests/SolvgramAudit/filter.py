from pathlib import Path
import json,re,subprocess
root=Path(__file__).resolve().parents[2]
stage=Path('/tmp/solvgram-audit-100023/filter');stage.mkdir(parents=True,exist_ok=True)
source=(root/'submodules/TelegramCore/Sources/Network/SolvgramRequestFilter.swift').read_text().replace('import SGSimpleSettings\n','')
(stage/'main.swift').write_text(source+'\n'+(Path(__file__).parent/'filter.swift').read_text())
schema=json.loads((root/'submodules/TelegramApi/schema.json').read_text())
constructors={x['predicate']:int(x['id']) & 0xffffffff for x in schema['constructors']}
tl=(root/'submodules/TelegramApi/swift_scheme.tl').read_text()
for predicate,value in [('boolTrue',0x997275b5),('messages.affectedMessages',0x84d19185),('vector',0x1cb5c415),('messages.sponsoredMessagesEmpty',0x1839490f)]:
    assert constructors[predicate] == value
    assert re.search(r'^'+re.escape(predicate)+r'#'+format(value,'x')+r'\b',tl,re.M),predicate
methods={x['method']:x['type'] for x in schema['methods']}
assert methods['messages.readHistory']=='messages.AffectedMessages'
assert methods['messages.readMessageContents']=='messages.AffectedMessages'
for name in ['channels.readHistory','messages.readDiscussion','messages.readSavedHistory','messages.readEncryptedHistory','channels.readMessageContents','stories.incrementStoryViews']:
    assert methods[name]=='Bool',name
subprocess.run(['swiftc','-swift-version','5','-O','-module-cache-path','/tmp/solvgram-audit-swift-cache',str(stage/'main.swift'),str(root/'Solvgram/SGSimpleSettings/Sources/SolvgramSettings.swift'),'-o',str(stage/'filter-audit')],check=True)
subprocess.run([str(stage/'filter-audit')],check=True)
print('TL_SCHEMA_AUDIT_OK constructors=4 responseTypes=8')
