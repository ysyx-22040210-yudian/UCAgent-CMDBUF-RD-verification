"""Verify the GitHub delivery bytes against the independently captured manifest."""

import hashlib
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'publication_manifest.json').read_text(encoding='utf-8'))
    failures = []
    for name, metadata in manifest['files'].items():
        path = (root / name).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file():
            failures.append({'file': name, 'reason': 'missing or unsafe path'})
            continue
        digest = hashlib.sha256()
        with path.open('rb') as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b''):
                digest.update(block)
        if path.stat().st_size != metadata['bytes'] or digest.hexdigest() != metadata['sha256']:
            failures.append({'file': name, 'reason': 'size or SHA256 mismatch'})
    result = {'status': 'failed' if failures else 'passed',
              'files': len(manifest['files']), 'failures': failures}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
