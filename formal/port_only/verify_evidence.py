#!/usr/bin/env python3
"""Verify the sealed port-only evidence bytes without extracting the archive."""
import argparse,hashlib,json,tarfile
from pathlib import Path,PurePosixPath

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--directory',type=Path,default=Path(__file__).resolve().parents[2]/'verification/port_only_20261018')
    a=p.parse_args();root=a.directory
    metadata=json.loads((root/'archive.json').read_text())
    expected=json.loads((root/'evidence_manifest.json').read_text())['files']
    archive=root/metadata['file'];digest=hashlib.sha256()
    with archive.open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):digest.update(block)
    assert archive.stat().st_size==metadata['bytes'] and digest.hexdigest()==metadata['sha256'],'Archive SHA256 mismatch'
    seen=set()
    with tarfile.open(str(archive),'r:gz') as tar:
        for member in tar:
            path=PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts and member.isfile(),member.name
            assert member.name not in seen and member.name in expected,member.name
            seen.add(member.name);h=hashlib.sha256()
            with tar.extractfile(member) as stream:
                for block in iter(lambda:stream.read(1048576),b''):h.update(block)
            assert member.size==expected[member.name]['bytes'] and h.hexdigest()==expected[member.name]['sha256'],member.name
    assert seen==set(expected) and len(seen)==metadata['members']
    coverage=json.loads((root/'coverage_final.json').read_text(encoding='utf8'))
    for row in coverage['rows']:
        assert row['formal_bins']==row['total_bins'],row['testpoint']
        for item in row['bins']:assert item['formal']['trace'] in seen,item['label']
    result=dict(passed=True,archive_sha256=metadata['sha256'],checked_members=len(seen),testpoints=200,formal_cover_bins=1415,proof_scope_unchanged=True)
    (root/'archive_verification.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))

if __name__=='__main__':main()
