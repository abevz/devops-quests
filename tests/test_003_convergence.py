"""A clean baseline plan is not convergence of an absent requested module."""

import os
import subprocess

import pytest

from devops_quests.catalog import Catalog


@pytest.mark.parametrize('address,plan,expected', [
    ('', 0, False), ('local_file.notice', 0, False),
    ('module.notice.local_file.notice', 0, True),
    ('module.notice.local_file.notice', 1, False),
    ('module.notice.local_file.notice', 2, False),
])
def test_003_convergence_requires_requested_module_and_empty_plan(tmp_path, address, plan, expected):
    tofu = tmp_path / 'tofu'
    tofu.write_text('#!/bin/bash\ncase "$1" in\n'
                    'state) printf "%s\\n" "$DQ_TEST_ADDRESS" ;;\n'
                    'plan) exit "$DQ_TEST_PLAN" ;;\n*) exit 99 ;;\nesac\n')
    tofu.chmod(0o755)
    check = Catalog().quests[3]['stages'][0]['objectives'][3]['check']
    result = subprocess.run(
        ['bash', '-euo', 'pipefail', '-c', check], text=True, capture_output=True,
        env={**os.environ, 'PATH': str(tmp_path) + ':' + os.environ['PATH'],
             'DQ_TEST_ADDRESS': address, 'DQ_TEST_PLAN': str(plan)},
    )
    assert (result.returncode == 0) == expected, result.stdout + result.stderr
    assert ('[DQ:condition_3]' in result.stdout) != expected
