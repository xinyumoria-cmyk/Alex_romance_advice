"""Verify the project, scan publication content, build checksums and a ZIP."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile
from reproduce import ROOT, reproduce, check, read, write

SKIP_DIRS = {'.git','__pycache__','build','dist','runs','.venv'}
SKIP_NAMES = {'MANIFEST.sha256.json'}
PATTERNS = {
    'credential': re.compile(rb'(?:sk-(?:proj-|svcacct-)?|nvapi-|ghp_|github_pat_)[A-Za-z0-9_-]{20,}'),
    'private_key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'local_user_path': re.compile(rb'[A-Za-z]:(?:\\\\|\\|/)Users(?:\\\\|\\|/)[^<>\r\n"]+'),
}

def files(root):
    return [p for p in sorted(root.rglob('*')) if p.is_file() and not set(p.relative_to(root).parts)&SKIP_DIRS and p.name not in SKIP_NAMES]

def scan(root=ROOT):
    checked = 0
    for path in files(root):
        check(not path.is_symlink(), 'Symlinks not permitted in release')
        check(not (path.name == '.env' or (path.name.startswith('.env.') and path.name != '.env.example')), 'Environment file in release')
        check(path.name not in {'auth.json','credentials','credentials.json'}, 'Authentication file in release')
        blobs = [(path.name, path.read_bytes())]
        if path.suffix == '.docx':
            with zipfile.ZipFile(path) as z:
                blobs = [(name, z.read(name)) for name in z.namelist()]
        for label, blob in blobs:
            for kind, pattern in PATTERNS.items():
                check(not pattern.search(blob), f'{kind} detected in {path.relative_to(root)} ({label}); value not printed')
        checked += 1
    return checked

def manifest(root=ROOT):
    return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files(root)}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Verify the existing checksum manifest only')
    args = parser.parse_args()
    if args.verify:
        check(read(ROOT / 'MANIFEST.sha256.json') == manifest(), 'Release checksums/file list differ')
        print(f'Checksums and secret scan passed: {scan()} files.')
        return
    report = reproduce()
    scan()
    write(ROOT / 'provenance/offline_verification.json', report)
    write(ROOT / 'MANIFEST.sha256.json', manifest())
    (ROOT / 'dist').mkdir(exist_ok=True)
    target = ROOT / 'dist/alex-advice-v3.zip'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in files(ROOT) + [ROOT / 'MANIFEST.sha256.json']:
            z.write(p, 'alex-advice-v3/' + p.relative_to(ROOT).as_posix())
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (target.parent / (target.name + '.sha256')).write_text(digest + '  ' + target.name + '\n', encoding='ascii')
    print(f'Packaged {len(files(ROOT))+1} files: {target.name}; SHA256 {digest}')

if __name__ == '__main__':
    main()
