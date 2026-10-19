#!/usr/bin/env python3
"""Record the README demo with the checkout's release binary and local Git only."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
ASSETS = Path(__file__).resolve().parent
WORK = ROOT / '.agent/readme-demo'
HOME = WORK / 'home'
SOURCE = HOME / 'team-rules'
PROJECT = HOME / 'project'
EXECUTABLE = (ROOT / '.build/release/agents').resolve()
ENV = {
    'HOME': str(HOME),
    'PATH': f'{HOME}/bin:/usr/bin:/bin:/usr/sbin:/sbin',
    'TMPDIR': str(HOME / 'tmp'),
    'LC_ALL': 'C',
    'TERM': 'dumb',
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_ALLOW_PROTOCOL': 'file',
    'GIT_AUTHOR_NAME': 'Demo',
    'GIT_AUTHOR_EMAIL': 'demo@example.invalid',
    'GIT_COMMITTER_NAME': 'Demo',
    'GIT_COMMITTER_EMAIL': 'demo@example.invalid',
    'GIT_AUTHOR_DATE': '2026-10-19T00:00:00Z',
    'GIT_COMMITTER_DATE': '2026-10-19T00:00:00Z',
}
FILES = {
    'skills/pdf/SKILL.md': (
        '---\nname: pdf\ndescription: Review PDF documents.\n---\n\n'
        'Inspect page sizes, annotations, and extracted text.\n'
    ),
    'instructions/code-review.md': '# Code review\n\nCheck correctness.\nReview code.\n',
    'instructions/commits.md': '# Commits\n\nUse clear messages.\n',
}
UPDATED = '# Code review\n\nCheck correctness.\nReview code and tests.\n'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def run(arguments, cwd=PROJECT, env=ENV):
    result = subprocess.run(arguments, cwd=cwd, env=env, capture_output=True,
                            text=True, check=True)
    if result.stderr:
        raise RuntimeError(result.stderr)
    return result.stdout


def main():
    if not EXECUTABLE.is_file():
        raise SystemExit('Build first: swift build -c release')
    if HOME.exists():
        raise SystemExit('Remove the previous .agent/readme-demo/home fixture first.')
    for directory in [HOME / 'bin', HOME / 'tmp', PROJECT, SOURCE]:
        directory.mkdir(parents=True)
    (HOME / 'bin/agents').symlink_to(EXECUTABLE)
    receipt = {'environment': ENV, 'commands': []}
    record = {'title': 'agents', 'commands': []}

    def capture(command):
        output = run(['/bin/sh', '-c', command])
        receipt['commands'].append({
            'command': command, 'stdout': output, 'stderr': '', 'exit_code': 0,
            'home_replacements': output.count(str(HOME)),
        })
        record['commands'].append({
            'command': command,
            'stdout': output.replace(str(HOME), '~').removesuffix('\n'),
            'exit_code': 0,
        })

    try:
        for name, content in FILES.items():
            path = SOURCE / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        run(['git', 'init', '--quiet', '--initial-branch=main'], SOURCE)
        run(['git', 'add', '.'], SOURCE)
        run(['git', 'commit', '--quiet', '-m', 'docs: add team guidance'], SOURCE)
        initial = run(['git', 'rev-parse', 'HEAD'], SOURCE).strip()
        capture('agents skills add ~/team-rules pdf')
        capture('agents instructions add ~/team-rules code-review commits')
        capture('agents watch add ~/team-rules')
        (SOURCE / 'instructions/code-review.md').write_text(UPDATED)
        capture('git -C ~/team-rules commit -qam "docs: review tests"')
        updated = run(['git', 'rev-parse', 'HEAD'], SOURCE).strip()
        capture('agents watch')
        capture('agents update --apply')
        assert UPDATED in (PROJECT / 'AGENTS.md').read_text()
        assert 'Use clear messages.' in (PROJECT / 'AGENTS.md').read_text()
        assert (PROJECT / '.agents/skills/pdf/SKILL.md').read_text() == FILES['skills/pdf/SKILL.md']
        provenance = {
            'source_revision': subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'executable': {
                'path': '.build/release/agents',
                'version': run(['agents', '--version']).strip(),
                'sha256': digest(EXECUTABLE.read_bytes()),
                'configuration': 'release',
            },
            'toolchain': subprocess.check_output(
                ['swift', '--version'], cwd=ROOT, text=True,
                stderr=subprocess.STDOUT).strip(),
            'git_version': run(['git', '--version']).strip(),
            'package_resolved_sha256': digest((ROOT / 'Package.resolved').read_bytes()),
            'dependencies': json.loads((ROOT / 'Package.resolved').read_text())['pins'],
            'fixture': {
                'source': '~/team-rules', 'project': '~/project', 'branch': 'main',
                'initial_revision': initial, 'updated_revision': updated,
                'initial_files': FILES,
                'updated_files': {'instructions/code-review.md': UPDATED},
                'initial_sha256': {name: digest(content.encode()) for name, content in FILES.items()},
                'updated_sha256': {'instructions/code-review.md': digest(UPDATED.encode())},
                'commit_identity': 'Demo <demo@example.invalid>',
                'commit_date': ENV['GIT_AUTHOR_DATE'],
            },
            'normalizations': [
                {
                    'from': '${WORKTREE}/.agent/readme-demo/home', 'to': '~',
                    'fields': ['commands[].stdout'],
                    'replacement_counts': [item['home_replacements'] for item in receipt['commands']],
                    'note': 'The CLI also abbreviates HOME to ~ in human output; shell commands use ~ directly.',
                },
                {
                    'operation': 'Remove one final LF from each command stdout for renderer spacing.',
                    'fields': ['commands[].stdout'],
                },
            ],
            'commands': [{
                'command': item['command'], 'exit_code': item['exit_code'],
                'stderr': item['stderr'],
            } for item in receipt['commands']],
            'network': 'Only local Git sources; GIT_ALLOW_PROTOCOL=file.',
            'record_sha256': digest((json.dumps(record, indent=2, ensure_ascii=False) + '\n').encode()),
        }
        save(ASSETS / 'record.json', record)
        save(ASSETS / 'provenance.json', provenance)
        save(WORK / 'receipt.json', receipt)
    finally:
        shutil.rmtree(HOME)


if __name__ == '__main__':
    main()
