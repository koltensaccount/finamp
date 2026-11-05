#!/usr/bin/env python3
"""Export or verify a revisioned guidance snapshot. Never deploy or access media."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from check_agent_guidance import DOCS, ROOT, check

WEB_ENTRY = '''\n## KB Music product and engineering guidance

Read [.kb-guidance/AGENTS.md](.kb-guidance/AGENTS.md) and
[.kb-guidance/VISION.md](.kb-guidance/VISION.md) before editing. These are a
revisioned snapshot of the canonical koltensaccount/finamp guidance, not a second
editable vision. Use [.kb-guidance/docs/agents/WEB_WORKSPACE.md](.kb-guidance/docs/agents/WEB_WORKSPACE.md)
and [.kb-guidance/docs/agents/QUALITY_GATES.md](.kb-guidance/docs/agents/QUALITY_GATES.md)
for source ownership, deployment boundaries, parity and verification.

This source has no Git metadata; record file hashes and workspace identity rather
than inventing a branch/revision. Preserve the generated Next.js block above.
The canonical lib/backend scope
guides apply when working on those services; this workspace's UI/API proxies
follow the PWA scope. Record task evidence under this workspace's
`docs/verification/` and coordinate compatibility with native/server revisions.
Check `.kb-guidance/manifest.json` against the current canonical revision before
cross-client changes; refresh through the exporter, never by hand-editing copies.
The adjacent Compose/auto-update scripts target Aubrey; do not run them for KB Music.
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(path):
    manifest = json.loads((path / 'manifest.json').read_text())
    for relative, expected in manifest['sha256'].items():
        target = (path / relative).resolve()
        if not target.is_relative_to(path.resolve()):
            raise ValueError(f'Invalid manifest path: {relative}')
        if digest(target) != expected:
            raise ValueError(f'Guidance drift: {relative}')
    print(f"Verified {len(manifest['sha256'])} files at {manifest['revision']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--output', type=Path)
    group.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        verify(args.verify)
        return
    errors = check()
    if errors:
        raise ValueError('\n'.join(errors))
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    # Snapshot provenance must describe committed bytes, not silently dirty docs.
    tracked = subprocess.check_output(['git', 'status', '--porcelain', '--', *DOCS], cwd=ROOT, text=True)
    if tracked:
        raise ValueError('Commit canonical guidance before exporting a revisioned snapshot')
    destination = args.output / '.kb-guidance'
    destination.mkdir(parents=True, exist_ok=False)
    hashes = {}
    for relative in DOCS:
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
        hashes[relative] = digest(target)
    # Makes the verification directory index link work in the generated snapshot.
    (destination / 'docs/verification').mkdir(exist_ok=True)
    manifest = {'repository': 'https://github.com/koltensaccount/finamp',
                'revision': revision, 'sha256': hashes}
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.output / 'WEB_ENTRYPOINT.md').write_text(WEB_ENTRY)
    (args.output / 'GEMINI.md').write_text(
        '# KB Music — Gemini / Antigravity\n\nRead and follow [AGENTS.md](AGENTS.md), including the canonical snapshot links.\n')
    (args.output / 'CLAUDE.md').write_text('# KB Music — Claude Code\n\n@AGENTS.md\n')
    (args.output / 'copilot-instructions.md').write_text(
        '# KB Music\n\nRead and follow [AGENTS.md](../AGENTS.md), including the canonical snapshot links.\n')
    verify(destination)
    print(f'Exported guidance only to {args.output}; no server changes performed.')


if __name__ == '__main__':
    main()
