#!/usr/bin/env python3
"""Verify sealed VM evidence members without extracting files or modifying results."""
import argparse,hashlib,json,tarfile
from pathlib import Path

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--evidence',type=Path,default=Path(__file__).resolve().parents[2]/'verification/corner_20261021')
    args=ap.parse_args();folder=args.evidence
    summary=json.loads((folder/'summary.json').read_text(encoding='utf-8'))
    archive=folder/summary['archive']['file']
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==summary['archive']['sha256'],'archive hash'
    expected=json.loads((folder/'evidence_manifest.json').read_text(encoding='utf-8'))
    with tarfile.open(archive,'r:gz') as tar:
        assert {m.name for m in tar.getmembers() if m.isfile()}==set(expected)|{'evidence_manifest.json'},'member list'
        assert json.loads(tar.extractfile('evidence_manifest.json').read())==expected,'embedded manifest'
        for name,meta in expected.items():
            data=tar.extractfile(name).read()
            assert len(data)==meta['bytes'],name
            assert hashlib.sha256(data).hexdigest()==meta['sha256'],name
    print(json.dumps({'status':'PASS','verified_members':len(expected),'archive':str(archive)}))

if __name__=='__main__':main()
