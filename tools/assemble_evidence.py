"""Reassemble the unchanged original evidence archive and verify every digest."""

import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Output archive path; defaults to verification/closure.')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'verification/closure'
    manifest = json.loads((root / 'evidence_parts.json').read_text(encoding='utf-8'))
    output = args.output or root / manifest['archive']
    if output.exists():
        raise SystemExit(f'Output already exists; inspect it first: {output}')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + '.partial')
    total_hash = hashlib.sha256()
    total_size = 0
    try:
        with temporary.open('xb') as destination:
            for part in manifest['parts']:
                source = (root / part['file']).resolve()
                if not source.is_relative_to(root.resolve()):
                    raise RuntimeError('Evidence part path escapes its directory.')
                part_hash = hashlib.sha256()
                part_size = 0
                with source.open('rb') as handle:
                    for block in iter(lambda: handle.read(1024 * 1024), b''):
                        destination.write(block)
                        part_hash.update(block)
                        total_hash.update(block)
                        part_size += len(block)
                        total_size += len(block)
                if part_size != part['bytes'] or part_hash.hexdigest() != part['sha256']:
                    raise RuntimeError(f'Part integrity check failed: {part["file"]}')
        if total_size != manifest['bytes'] or total_hash.hexdigest() != manifest['sha256']:
            raise RuntimeError('Reassembled archive integrity check failed.')
        temporary.rename(output)
    except Exception:
        if temporary.exists():
            temporary.unlink()
        raise
    print(json.dumps({'status': 'passed', 'archive': str(output), 'bytes': total_size,
                      'sha256': total_hash.hexdigest()}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
