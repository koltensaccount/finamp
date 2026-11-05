#!/usr/bin/env python3
"""Check the guidance graph and require reviewable evidence for behavior diffs."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
ENTRYPOINTS = ('AGENTS.md', 'GEMINI.md', 'CLAUDE.md', '.github/copilot-instructions.md')
DOCS = (
    *ENTRYPOINTS, 'VISION.md', 'lib/AGENTS.md', 'backend/AGENTS.md',
    'docs/PROJECT_BRIEF.md', 'docs/ARCHITECTURE.md', 'docs/DECISIONS.md',
    'docs/CURRENT_STATE.md', 'docs/NEXT_TASK.md', 'docs/agents/RESEARCH.md',
    'docs/agents/QUALITY_GATES.md', 'docs/agents/WEB_WORKSPACE.md',
    'docs/verification/TEMPLATE.md', '.github/PULL_REQUEST_TEMPLATE.md',
)


def evidence_required(paths):
    """Recognize behavior changes, including tests, platform and deployment code."""
    return any(
        (p.startswith(('lib/', 'backend/', 'test/', 'integration_test/', 'ios/',
                       'macos/', 'android/', 'linux/', 'windows/', 'assets/'))
         and not p.endswith('.md'))
        or p in ('pubspec.yaml', 'pubspec.lock', '.flutter-version', '.fvmrc', 'appcast.xml')
        or (p.startswith('.github/workflows/') and p != '.github/workflows/agent-guidance.yml')
        for p in paths
    )


def check(root=ROOT, changed=None):
    errors = []
    for name in DOCS:
        path = root / name
        if not path.is_file():
            errors.append(f'Missing guidance file: {name}')
            continue
        content = path.read_text()
        # Bound always-loaded policy; richer docs stay linked, not copied.
        if name in ENTRYPOINTS or name in ('lib/AGENTS.md', 'backend/AGENTS.md'):
            limit = 6000 if name == 'AGENTS.md' else 3500
            if len(content.encode()) > limit:
                errors.append(f'Entrypoint exceeds {limit} bytes: {name}')
        for target in re.findall(r'\]\(([^)]+)\)', content):
            if re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target) or target.startswith('#'):
                continue
            relative = unquote(target.split('#', 1)[0])
            if relative and not (path.parent / relative).exists():
                errors.append(f'Broken local link: {name} -> {target}')
    root_text = (root / 'AGENTS.md').read_text() if (root / 'AGENTS.md').exists() else ''
    for required in ('VISION.md', 'lib/AGENTS.md', 'backend/AGENTS.md', 'QUALITY_GATES.md'):
        if required not in root_text:
            errors.append(f'Root does not route to {required}')
    for adapter in ENTRYPOINTS[1:]:
        path = root / adapter
        if path.exists() and 'AGENTS.md' not in path.read_text():
            errors.append(f'Adapter does not reference canonical contract: {adapter}')
    if (root / 'CLAUDE.md').exists() and '\n@AGENTS.md\n' not in (root / 'CLAUDE.md').read_text():
        errors.append('Claude adapter must import @AGENTS.md')
    # Limit stale-rule matching to active policy, not explicitly retained history.
    for name in ('AGENTS.md', 'lib/AGENTS.md', 'backend/AGENTS.md', 'docs/PROJECT_BRIEF.md'):
        path = root / name
        if path.exists() and re.search(r'No visual redesign\.|No visual redesign yet\.', path.read_text()):
            errors.append(f'Obsolete blanket redesign prohibition: {name}')
    for path in root.rglob('AGENTS.override.md'):
        if '.git' not in path.parts:
            errors.append(f'Unexpected policy-shadowing override: {path.relative_to(root)}')
    if changed is not None and evidence_required(changed):
        reports = [p for p in changed if p.startswith('docs/verification/')
                   and p.endswith('.md') and p != 'docs/verification/TEMPLATE.md'
                   and (root / p).is_file()]
        if not reports:
            errors.append('Behavior diff needs a changed task report in docs/verification/')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', help='Git revision to compare; enforce changed evidence report')
    args = parser.parse_args()
    changed = None
    if args.base:
        changed = subprocess.check_output(
            ['git', 'diff', '--name-only', f'{args.base}...HEAD'], cwd=ROOT, text=True
        ).splitlines()
    errors = check(changed=changed)
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print('Guidance links, scope routing and adapters pass; runtime adherence is not certified.')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
