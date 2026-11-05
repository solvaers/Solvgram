import importlib.util
from datetime import datetime, timezone
from pathlib import Path

root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('solvgram_version',root/'build-system/SolvgramVersion.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
n=module.next_build_number
early=datetime(2000,1,1,0,tzinfo=timezone.utc)   # date floor 1000 00 -> below every tag
late=datetime(2026,11,5,14,tzinfo=timezone.utc)  # date floor 2630914
assert n([],early) == 100001
assert n(['v13.1.1-100022','v13.0-100009'],early) == 100023
assert n(['unrelated','v13.1.1-100022-other','v13.1.1-0'],early) == 100001
assert n([' v14.0.1-200000\n','v13.1.1-100023'],early) == 200001
assert n(['v1.0','v1.1'],early) == 100001                     # new tags carry no build
assert n(['v13.1.1-100036','v1.0'],late) == 2630914          # date floor wins
assert n(['v13.1.1-3000000'],late) == 3000001                # never goes backwards
assert n([],late) < 2**31                                    # stays inside Int32
print('RELEASE_VERSION_AUDIT_OK cases=8')
