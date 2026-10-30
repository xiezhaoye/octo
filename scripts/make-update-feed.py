#!/usr/bin/env python3
"""Generate the update feed from the exact versioned ZIP being published."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
from zipfile import ZipFile

parser = argparse.ArgumentParser()
parser.add_argument('archive', type=Path)
parser.add_argument('--output', type=Path, default=Path('.release/latest.json'))
args = parser.parse_args()
with ZipFile(args.archive) as archive:
    info = plistlib.loads(archive.read('Octo.app/Contents/Info.plist'))
version = info['CFBundleShortVersionString']
expected = f'Octo-{version}-macos-arm64.zip'
if args.archive.name != expected or info['CFBundleIdentifier'] != 'com.xiezhaoye.dualpane':
    parser.error('安装包名称或应用标识不匹配')
notes = []
changelog = Path(__file__).resolve().parent.parent / 'CHANGELOG.md'
collect = False
for line in changelog.read_text().splitlines():
    if line.startswith('## '):
        if collect:
            break
        collect = line.startswith(f'## {version} ')
    elif collect and line.startswith('- '):
        notes.append(line[2:])
feed = {
    'version': version,
    'build': int(info['CFBundleVersion']),
    'minimumSystemVersion': info['LSMinimumSystemVersion'],
    'architecture': 'arm64',
    'downloadURL': f'https://octo-dl.xiezhaoye.site/{expected}',
    'sha256': hashlib.file_digest(args.archive.open('rb'), 'sha256').hexdigest(),
    'bytes': args.archive.stat().st_size,
    'notes': notes,
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + '\n')
print(f'{args.output}: {version} ({feed["build"]}), {feed["bytes"]} bytes')
