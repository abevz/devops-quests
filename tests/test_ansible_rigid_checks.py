"""Check the actual inline predicates with reference/equivalent/wrong artifacts.

Ansible/Jinja rendering runs in the qualified workstation, not a different host
fixture. The remaining inline predicates need only the project's PyYAML.
"""

import json
import os
import re
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def program(quest, tag, occurrence=0):
    source = (ROOT / f"quests/{quest:03}/check-0.sh").read_text()
    return source.split(f"<<'{tag}'\n")[occurrence + 1].split(f"\n{tag}", 1)[0]


def check_environment(tmp_path):
    data = tmp_path / "inventory.json"
    if not data.exists():
        data.write_text(
            json.dumps(
                {
                    "_meta": {"hostvars": {}},
                    "all": {"children": ["fleet"]},
                    "fleet": {"hosts": ["app1", "app2", "app3"]},
                }
            )
        )
    binary = tmp_path / "fixture-bin"
    binary.mkdir(exist_ok=True)
    cli = binary / "ansible-inventory"
    cli.write_text(
        "#!"
        + sys.executable
        + "\nimport sys,pathlib\nassert sys.argv[1:]==['--list']\nprint(pathlib.Path('inventory.json').read_text())\n"
    )
    cli.chmod(0o755)
    if not (tmp_path / "ansible.cfg").exists():
        (tmp_path / "ansible.cfg").write_text("[defaults]\ninventory=inventory.ini\n")
    if not (tmp_path / "inventory.ini").exists():
        hosts = json.loads(data.read_text()).get("fleet", {}).get("hosts", [])
        (tmp_path / "inventory.ini").write_text(
            "[fleet]\n" + "".join(host + "\n" for host in hosts)
        )
    return {**os.environ, "PATH": str(binary) + ":" + os.environ["PATH"]}


def probe(tmp_path, quest, tag, play=None, files=None):
    if play is not None:
        (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    for name, contents in (files or {}).items():
        (tmp_path / name).write_text(contents)
    code = program(quest, tag)
    if quest == 96:
        # Only remap the immutable backend receipt to this fixture's trusted path.
        code = code.replace(
            "/run/dq/facts/0/artifact.sha256", str(tmp_path / "trusted.sha256")
        )
    return subprocess.run(
        [sys.executable, "-"],
        input=code,
        cwd=tmp_path,
        env=check_environment(tmp_path),
        capture_output=True,
        text=True,
        timeout=10,
    )


def expect(result, good):
    for incidental in (
        "NameError:",
        "UnboundLocalError:",
        "ModuleNotFoundError:",
        "SyntaxError:",
    ):
        assert incidental not in result.stderr, result.stderr
    assert (result.returncode == 0) is good, result.stdout + result.stderr


def reload(name="Reload banner", argv=False):
    return {
        "name": name,
        "command": {"argv": ["dq-service", "reload"]} if argv else "dq-service reload",
    }


@pytest.mark.parametrize(
    "representation", ["reference", "equivalent", "wrong", "wrong_family"]
)
def test_012_required_json_fields_allow_unrelated_metadata(tmp_path, representation):
    # Execute the real remote Python body; do not replace SSH with a different predicate.
    source = yaml.safe_load((ROOT / "quests/012/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][0]["check"]
    code = re.search(r"import json;.*?assert .*?(?='\"'\"')", source)[0]
    record = {"family": "Debian", "architecture": "x86_64"}
    if representation == "equivalent":
        record["hostname"] = "app1"
    if representation == "wrong":
        record["architecture"] = "arm64"
    if representation == "wrong_family":
        record["family"] = "Fedora"
    path = tmp_path / "facts.json"
    path.write_text(json.dumps(record))
    result = subprocess.run(
        [sys.executable, "-c", code.replace("/srv/site/facts.json", str(path))],
        capture_output=True,
        text=True,
    )
    expect(result, representation in ("reference", "equivalent"))


@pytest.mark.parametrize(
    "quest,path,tag",
    [
        (25, "/tmp/idempotence-second.log", "DQ_RECAP"),
        (35, "probe.log", "DQ_RECAP"),
        (46, "verification.log", "DQ_RECAP"),
        (74, "check.log", "DQ_RECAP"),
        (79, "second.log", "DQ_RECAP"),
    ],
)
@pytest.mark.parametrize(
    "representation",
    ["reference", "equivalent", "runner", "wrong", "missing", "duplicate", "fraction"],
)
def test_distinct_host_recaps_accept_structured_and_reordered_output(
    tmp_path, quest, path, tag, representation
):
    positive = quest == 74
    values = {
        "changed": 2 if positive else 0,
        "failed": 0,
        "unreachable": 0,
        "skipped": 1,
    }
    rows = {"app" + str(host): dict(values) for host in (1, 2, 3)}
    if representation == "wrong":
        rows["app2"]["failed"] = 1
    if representation == "missing":
        del rows["app3"]
    if representation == "runner":
        counters = {"processed": {host: 1 for host in rows}}
        for key in values:
            counters[{"failed": "failures", "unreachable": "dark"}.get(key, key)] = {
                host: row[key] for host, row in rows.items()
            }
        text = json.dumps({"event": "playbook_on_stats", "event_data": counters})
    elif representation == "equivalent":
        for row in rows.values():
            row["failures"] = str(row.pop("failed"))
        text = json.dumps({"plays": [], "stats": rows})
    else:
        text = "PLAY RECAP ***\n" + "\n".join(
            host
            + " : "
            + " ".join(
                key + "=" + str(row[key])
                for key in ("failed", "skipped", "unreachable", "changed")
            )
            for host, row in rows.items()
        )
        if representation == "duplicate":
            text += "\napp1 : failed=0 skipped=1 unreachable=0 changed=0\n"
    if representation == "fraction":
        text = text.replace("failed=0", "failed=0.5")
    (tmp_path / "recap.log").write_text(text)
    code = program(quest, tag).replace(path, str(tmp_path / "recap.log"))
    result = subprocess.run(
        [sys.executable, "-"],
        input=code,
        cwd=tmp_path,
        env=check_environment(tmp_path),
        capture_output=True,
        text=True,
    )
    expect(result, representation in ("reference", "equivalent", "runner"))


@pytest.mark.parametrize("representation", ["reference", "equivalent", "wrong"])
def test_035_real_unreachable_evidence(tmp_path, representation):
    text = 'fatal: [probe]: UNREACHABLE! => {"unreachable": true}\n'
    if representation == "equivalent":
        text = json.dumps(
            {"event": "runner_on_unreachable", "event_data": {"host": "probe"}}
        )
    if representation == "wrong":
        text = json.dumps({"stats": {"probe": {"unreachable": 0}}})
    expect(
        probe(tmp_path, 35, "DQ_UNREACHABLE", files={"probe.log": text}),
        representation != "wrong",
    )


@pytest.mark.parametrize(
    "representation", ["reference", "equivalent", "wrong", "parallel", "extra_play"]
)
def test_028_task_name_is_not_the_serial_contract(tmp_path, representation):
    label = (
        "Deliver the route message"
        if representation == "reference"
        else "Publish the same banner"
    )
    hosts = ["app1", "app2", "app3"]
    if representation == "wrong":
        hosts = ["app2", "app1", "app3"]
    serial = (
        2
        if representation == "parallel"
        else (["33%", "1"] if representation == "equivalent" else 1)
    )
    play = [
        {
            "hosts": "fleet",
            "serial": serial,
            "tasks": [
                {
                    "name": label,
                    "copy": {
                        "dest": "/srv/site/message",
                        "content": "north-ready",
                        "mode": "0644",
                    },
                }
            ],
        }
    ]
    trace = "\n".join(
        json.dumps(event)
        for host in hosts
        for event in ({"task": label}, {"host": host, "task": label})
    )
    if representation == "extra_play":
        play.append(
            {
                "hosts": "fleet",
                "tasks": [
                    {"name": "Read the banner", "stat": {"path": "/srv/site/message"}}
                ],
            }
        )
        trace += "\n" + "\n".join(
            json.dumps({"host": host, "task": "Read the banner"}) for host in hosts
        )
    expect(
        probe(tmp_path, 28, "CHECK", play, {"rollout-events.jsonl": trace}),
        representation in ("reference", "equivalent", "extra_play"),
    )


def scope_play():
    return [
        {
            "hosts": "fleet",
            "serial": 1,
            "handlers": [reload()],
            "tasks": [
                {
                    "block": [{"debug": {"msg": "candidate"}}],
                    "rescue": [
                        {
                            "ansible.builtin.copy": {
                                "src": "previous.txt",
                                "dest": "/srv/site/message",
                                "mode": "0644",
                            },
                            "notify": "Reload banner",
                        }
                    ],
                    "always": [{"debug": {"msg": "checked"}}],
                }
            ],
        }
    ]


@pytest.mark.parametrize(
    "representation",
    ["reference", "equivalent", "wrong", "parallel", "no_block", "wrong_handler"],
)
def test_063_recovery_property_and_one_host_batches(tmp_path, representation):
    play = scope_play()
    task = play[0]["tasks"][0]
    if representation == "equivalent":
        play[0]["serial"] = ["33%", "1"]
        play[0]["hosts"] = ["fleet"]
        task["rescue"][0] = {
            "copy": {
                "src": "previous.txt",
                "dest": "/srv/site/message",
                "mode": 420,
                "backup": False,
            },
            "notify": ["Bring back banner"],
        }
        play[0]["handlers"] = [reload("Bring back banner", argv=True)]
        play[0]["tasks"].insert(0, {"debug": {"msg": "starting"}})
    if representation == "wrong":
        task["rescue"][0]["ansible.builtin.copy"]["src"] = "candidate.txt"
    if representation == "parallel":
        play[0]["serial"] = "100%"
    if representation == "no_block":
        del task["block"]
    if representation == "wrong_handler":
        play[0]["handlers"][0]["command"] = "echo no-reload"
    expect(
        probe(tmp_path, 63, "SCOPE", play),
        representation in ("reference", "equivalent"),
    )


@pytest.mark.parametrize(
    "representation", ["reference", "equivalent", "wrong", "override"]
)
def test_069_effective_no_log_cannot_be_replaced_by_a_clean_log(
    tmp_path, representation
):
    play = [
        {
            "hosts": "fleet",
            "tasks": [
                {
                    "ansible.builtin.copy": {
                        "dest": "/srv/site/station-token",
                        "mode": "0600",
                        "content": "credential",
                    },
                    "no_log": True,
                }
            ],
        }
    ]
    if representation == "equivalent":
        task = play[0]["tasks"][0]
        del task["no_log"]
        task["copy"] = task.pop("ansible.builtin.copy")
        task["copy"]["mode"] = 384
        play[0]["tasks"] = [{"block": [task], "no_log": "yes"}]
    if representation == "wrong":
        play[0]["tasks"][0]["no_log"] = False
    if representation == "override":
        play[0]["no_log"] = True
        play[0]["tasks"][0]["no_log"] = False
    expect(
        probe(tmp_path, 69, "SECRET", play),
        representation in ("reference", "equivalent"),
    )


@pytest.mark.parametrize(
    "representation", ["reference", "equivalent", "wrong", "mutating", "masked"]
)
def test_046_inspection_is_read_only_across_tag_layouts(tmp_path, representation):
    deploy = {
        "ansible.builtin.copy": {"dest": "/srv/site/banner.txt", "content": "banner"},
        "tags": ["deploy"],
    }
    inspect = {
        "ansible.builtin.stat": {"path": "/srv/site/banner.txt"},
        "tags": ["inspect"],
    }
    play = [{"hosts": "fleet", "tasks": [deploy, inspect]}]
    if representation == "equivalent":
        inspect["stat"] = inspect.pop("ansible.builtin.stat")
        inspect["stat"]["get_checksum"] = False
        del inspect["tags"]
        deploy["tags"] = "deploy"
        play[0]["tasks"] = [deploy, {"block": [inspect], "tags": "inspect"}]
        play[0]["handlers"] = []
    if representation == "wrong":
        inspect["ansible.builtin.stat"]["path"] = "/wrong"
    if representation == "mutating":
        deploy["tags"].append("inspect")
    if representation == "masked":
        inspect["changed_when"] = True
    expect(
        probe(tmp_path, 46, "TAGS", play), representation in ("reference", "equivalent")
    )


@pytest.mark.parametrize(
    "representation",
    ["reference", "equivalent", "wrong", "forced", "always_check", "masked"],
)
def test_074_preview_observer_is_read_only_and_skips_in_check_mode(
    tmp_path, representation
):
    play = [
        {
            "hosts": "fleet",
            "handlers": [reload()],
            "tasks": [
                {
                    "copy": {
                        "dest": "/srv/site/message",
                        "content": "north-74\n",
                        "mode": "0644",
                    },
                    "notify": "Reload banner",
                },
                {"command": "cat /run/quest-service.pid", "changed_when": False},
            ],
        }
    ]
    task = play[0]["tasks"][1]
    if representation == "equivalent":
        task["command"] = {"argv": ["cat", "/run/quest-service.pid"]}
        task["changed_when"] = "false"
        task["check_mode"] = "{{ ansible_check_mode }}"
        play[0]["tasks"][0]["copy"]["mode"] = 420
        play[0]["handlers"] = [reload(argv=True)]
    if representation == "wrong":
        task["command"] = "cat /wrong"
    if representation == "forced":
        task["check_mode"] = False
    if representation == "always_check":
        task["check_mode"] = True
    if representation == "masked":
        task["changed_when"] = True
    expect(
        probe(tmp_path, 74, "CHECK_MODE_TASK", play),
        representation in ("reference", "equivalent"),
    )


@pytest.mark.parametrize(
    "representation",
    ["reference", "equivalent", "wrong", "masked", "extra_action", "wrong_handler"],
)
def test_079_honest_fleet_convergence(tmp_path, representation):
    play = [
        {
            "hosts": "fleet",
            "handlers": [reload()],
            "tasks": [
                {
                    "file": {
                        "path": "/srv/site/config",
                        "state": "directory",
                        "mode": "0755",
                    }
                },
                {
                    "copy": {
                        "dest": "/srv/site/message",
                        "content": "north-79\n",
                        "mode": "0644",
                    },
                    "notify": "Reload banner",
                },
                {
                    "copy": {
                        "dest": "/srv/site/config/route",
                        "content": "route=north\n",
                        "mode": "0644",
                    }
                },
            ],
        }
    ]
    if representation == "equivalent":
        play[0]["handlers"] = [reload("Apply banner", argv=True)]
        task = play[0]["tasks"][1]
        task["notify"] = ["Apply banner"]
        task["copy"].update(content="north-79", mode=420, backup=False, owner="root")
        play[0]["tasks"] = [{"block": play[0]["tasks"], "tags": ["fleet"]}]
        play[0]["pre_tasks"] = []
    if representation == "wrong":
        play[0]["tasks"][2]["copy"]["content"] = "route=south\n"
    if representation == "masked":
        play[0]["tasks"][1]["changed_when"] = False
    if representation == "extra_action":
        play[0]["tasks"][1]["shell"] = "echo wrong"
    if representation == "wrong_handler":
        play[0]["handlers"][0]["command"] = "echo no-reload"
    expect(
        probe(tmp_path, 79, "DQ_FLEET", play),
        representation in ("reference", "equivalent"),
    )


def integrity_play():
    digest = "0123456789abcdef" * 4
    return digest, [
        {
            "hosts": "fleet",
            "serial": 1,
            "vars": {"expected_sha256": digest},
            "handlers": [reload("Reload station")],
            "tasks": [
                {
                    "ansible.builtin.stat": {
                        "path": "{{ playbook_dir }}/recovery.tar",
                        "checksum_algorithm": "sha256",
                    },
                    "delegate_to": "localhost",
                    "run_once": True,
                    "register": "artifact",
                },
                {
                    "ansible.builtin.assert": {
                        "that": ["artifact.stat.checksum == expected_sha256"]
                    }
                },
                {
                    "ansible.builtin.unarchive": {
                        "src": "recovery.tar",
                        "dest": "/srv/site",
                        "owner": "root",
                        "group": "root",
                        "mode": "0644",
                    },
                    "notify": "Reload station",
                },
            ],
        }
    ]


@pytest.mark.parametrize(
    "representation",
    ["reference", "equivalent", "wrong", "partial", "after_restore", "earlier_play"],
)
def test_096_complete_trusted_checksum_is_verified_before_restore(
    tmp_path, representation
):
    digest, play = integrity_play()
    if representation == "equivalent":
        play[0]["vars"] = {"trusted_archive": digest}
        task = play[0]["tasks"][0]
        task["stat"] = task.pop("ansible.builtin.stat")
        task["register"] = "receipt"
        play[0]["tasks"][1] = {
            "assert": {"that": "trusted_archive == receipt['stat']['checksum']"}
        }
    if representation == "wrong":
        play[0]["tasks"][1]["ansible.builtin.assert"]["that"] = [
            "expected_sha256 == expected_sha256"
        ]
    if representation == "partial":
        play[0]["tasks"][1]["ansible.builtin.assert"]["that"] = [
            "artifact.stat.checksum[:8] == expected_sha256[:8]"
        ]
    if representation == "after_restore":
        play[0]["tasks"][1], play[0]["tasks"][2] = (
            play[0]["tasks"][2],
            play[0]["tasks"][1],
        )
    if representation == "earlier_play":
        play.insert(
            0,
            {
                "hosts": "fleet",
                "serial": 1,
                "handlers": [reload("Reload station")],
                "tasks": [play[0]["tasks"][2]],
            },
        )
    expect(
        probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}),
        representation in ("reference", "equivalent"),
    )


@pytest.mark.parametrize(
    "form", ["relative", "playbook_dir", "actual_absolute", "different_absolute", "legacy_root"]
)
def test_096_checksum_guard_binds_the_actual_controller_archive(tmp_path, form):
    import hashlib

    contents = b"trusted controller archive bytes"
    digest, play = integrity_play()
    digest = hashlib.sha256(contents).hexdigest()
    play[0]["vars"]["expected_sha256"] = digest
    (tmp_path / "recovery.tar").write_bytes(contents)
    (tmp_path / "other.tar").write_bytes(contents)
    paths = {
        "relative": "recovery.tar",
        "playbook_dir": "{{ playbook_dir }}/recovery.tar",
        "actual_absolute": str(tmp_path / "recovery.tar"),
        "different_absolute": str(tmp_path / "other.tar"),
        "legacy_root": "/root/quest/recovery.tar",
    }
    play[0]["tasks"][0]["ansible.builtin.stat"]["path"] = paths[form]
    expect(
        probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}),
        form in {"relative", "playbook_dir", "actual_absolute"},
    )


@pytest.mark.parametrize("occurrence", [1, 2])
@pytest.mark.parametrize(
    "form", ["relative", "playbook_dir", "actual_absolute", "different_absolute", "legacy_root"]
)
def test_096_restore_source_is_the_actual_controller_archive(tmp_path, form, occurrence):
    _, play = integrity_play()
    paths = {
        "relative": "recovery.tar",
        "playbook_dir": "{{ playbook_dir }}/recovery.tar",
        "actual_absolute": str(tmp_path / "recovery.tar"),
        "different_absolute": str(tmp_path / "other.tar"),
        "legacy_root": "/root/quest/recovery.tar",
    }
    play[0]["tasks"][2]["ansible.builtin.unarchive"]["src"] = paths[form]
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    result = subprocess.run(
        [sys.executable, "-"],
        input=program(96, "VERIFY", occurrence),
        cwd=tmp_path,
        env=check_environment(tmp_path),
        capture_output=True,
        text=True,
        timeout=10,
    )
    expect(result, form in {"relative", "playbook_dir", "actual_absolute"})


@pytest.mark.parametrize(
    "representation",
    ["reference", "equivalent", "wrong", "parallel", "untrusted_source"],
)
def test_096_restore_properties_not_dictionary_bytes(tmp_path, representation):
    _, play = integrity_play()
    if representation == "equivalent":
        play[0]["serial"] = "33%"
        task = play[0]["tasks"][2]
        task["unarchive"] = task.pop("ansible.builtin.unarchive")
        task["unarchive"].update(mode=420, owner="0", group=0, remote_src=False)
        play[0]["handlers"] = [reload("Reload station", argv=True)]
    if representation == "wrong":
        play[0]["tasks"][2]["ansible.builtin.unarchive"]["mode"] = "0600"
    if representation == "parallel":
        play[0]["serial"] = [1, 2]
    if representation == "untrusted_source":
        play[0]["tasks"][2]["ansible.builtin.unarchive"]["src"] = "other.tar"
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    code = program(96, "VERIFY", 1)
    result = subprocess.run(
        [sys.executable, "-"],
        input=code,
        cwd=tmp_path,
        env=check_environment(tmp_path),
        capture_output=True,
        text=True,
    )
    expect(result, representation in ("reference", "equivalent"))


@pytest.mark.parametrize("representation", ["reference", "equivalent", "wrong"])
def test_038_exact_defaults_remain_exact(tmp_path, representation):
    source = yaml.safe_load((ROOT / "quests/038/quest.yaml").read_text())["stages"][0][
        "objectives"
    ][1]["check"]
    (tmp_path / "roles/station/defaults").mkdir(parents=True)
    settings = {"route": "retired", "platform": "shared"}
    if representation == "wrong":
        settings["extra"] = "not supplied"
    (tmp_path / "roles/station/defaults/main.yml").write_text(
        yaml.safe_dump(
            settings,
            default_flow_style=representation == "equivalent",
            sort_keys=representation != "equivalent",
        )
    )
    result = subprocess.run(
        ["bash", "-c", source],
        cwd=tmp_path,
        env=check_environment(tmp_path),
        capture_output=True,
        text=True,
    )
    expect(result, representation != "wrong")


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Requires the qualified workstation's Ansible/Jinja runtime",
)
@pytest.mark.parametrize(
    "representation",
    [
        "reference",
        "equivalent",
        "wrong",
        "not_once",
        "not_local",
        "role_writer",
        "always_writer",
        "never_writer",
        "command_writer",
        "external_binding",
        "notify_writer",
    ],
)
def test_032_dynamic_report_in_the_real_workstation(tmp_path, representation):
    # A fresh owned, short-lived workstation, not another app's persistent runtime.
    # The native matrix separately verifies managed-host outcomes and production exec.
    image = os.environ.get("DQ_ANSIBLE_TEST_IMAGE")
    assert image, "Set an owned test image; never borrow a preview container"
    task = {
        "ansible.builtin.copy": {
            "dest": "{{ playbook_dir }}/fleet.txt",
            "content": "{% for host in groups['fleet'] | sort %}{{ host }}\n{% endfor %}",
        },
        "delegate_to": "localhost",
        "run_once": True,
    }
    play = [{"hosts": "fleet", "tasks": [task]}]
    if representation == "equivalent":
        task["local_action"] = {"module": "copy", **task.pop("ansible.builtin.copy")}
        del task["delegate_to"]
        task["local_action"]["content"] = (
            "{{ ansible_play_hosts_all | sort | join('\\n') }}\n"
        )
        task["run_once"] = "yes"
    if representation == "wrong":
        task["ansible.builtin.copy"]["content"] = "app1\napp2\napp3\n"
    if representation == "not_once":
        task["run_once"] = False
    if representation == "not_local":
        task["delegate_to"] = "app1"
    if representation == "role_writer":
        play[0]["roles"] = ["second_report_writer"]
        role = tmp_path / "roles/second_report_writer/tasks/main.yml"
        role.parent.mkdir(parents=True)
        role.write_text(
            yaml.safe_dump(
                [
                    {
                        "copy": {
                            "dest": "{{ playbook_dir }}/fleet.txt",
                            "content": "app1\napp2\napp3\n",
                        },
                        "delegate_to": "localhost",
                    }
                ]
            )
        )
    if representation == "always_writer":
        play[0]["tasks"] = [
            {
                "block": [task],
                "always": [
                    {
                        "copy": {
                            "dest": "{{ playbook_dir }}/fleet.txt",
                            "content": "app1\napp2\napp3\n",
                        },
                        "delegate_to": "localhost",
                        "run_once": True,
                    }
                ],
            }
        ]
    if representation == "never_writer":
        task["tags"] = "never"
    if representation == "command_writer":
        play[0]["tasks"].append(
            {
                "command": "sh -c 'printf hardcoded > {{ playbook_dir }}/fleet.txt'",
                "delegate_to": "localhost",
            }
        )
    if representation == "external_binding":
        play[0]["vars"] = {"body": "{{ groups.fleet | sort | join('\\n') }}\n"}
        task["ansible.builtin.copy"]["content"] = "{{ body }}"
        play[0]["vars_files"] = ["overrides.yml"]
        (tmp_path / "overrides.yml").write_text(
            yaml.safe_dump({"body": "app1\napp2\napp3\n"})
        )
    if representation == "notify_writer":
        task["notify"] = "Overwrite report"
        play[0]["handlers"] = [
            {
                "name": "Overwrite report",
                "copy": {
                    "dest": "{{ playbook_dir }}/fleet.txt",
                    "content": "app1\napp2\napp3\n",
                },
                "delegate_to": "localhost",
            }
        ]
    (tmp_path / "ansible.cfg").write_text("[defaults]\ninventory=inventory.ini\n")
    (tmp_path / "inventory.ini").write_text("[fleet]\napp1\napp2\napp3\n")
    fixture = tmp_path / "rollout.yml"
    fixture.write_text(yaml.safe_dump(play))
    result = subprocess.run(
        [
            "docker",
            "--host",
            "unix:///var/run/docker.sock",
            "run",
            "--rm",
            "--entrypoint",
            "python3",
            "--mount",
            f"type=bind,src={tmp_path},dst=/proof,readonly",
            "--workdir",
            "/proof",
            image,
            "-I",
            "-c",
            program(32, "DQ_DELEGATION"),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    expect(result, representation in ("reference", "equivalent"))


@pytest.mark.parametrize("branch", ["rescue", "always"])
def test_046_hidden_inspection_mutation_is_rejected(tmp_path, branch):
    deploy = {
        "copy": {"dest": "/srv/site/banner.txt", "content": "north-46"},
        "tags": "deploy",
    }
    inspect = {"stat": {"path": "/srv/site/banner.txt"}}
    block = {
        "block": [inspect],
        "tags": "inspect",
        branch: [
            {
                "copy": {"dest": "/tmp/unsafe", "content": "changed"},
                "changed_when": False,
            }
        ],
    }
    expect(
        probe(tmp_path, 46, "TAGS", [{"hosts": "fleet", "tasks": [deploy, block]}]),
        False,
    )


def test_046_static_path_variables_and_read_only_always_are_equivalent(tmp_path):
    play = [
        {
            "hosts": "fleet",
            "vars": {"banner_path": "/srv/site/banner.txt"},
            "tasks": [
                {
                    "copy": {"dest": "{{ banner_path }}", "content": "north-46"},
                    "tags": "deploy",
                },
                {
                    "block": [
                        {"stat": {"path": "{{ banner_path }}", "get_checksum": False}}
                    ],
                    "always": [{"debug": {"msg": "inspection complete"}}],
                    "tags": "inspect",
                },
            ],
        }
    ]
    expect(probe(tmp_path, 46, "TAGS", play), True)


@pytest.mark.parametrize("control", ["when", "check_mode", "ignore_errors"])
def test_063_inactive_recovery_block_is_not_certified(tmp_path, control):
    play = scope_play()
    play[0]["tasks"][0][control] = False if control == "when" else True
    expect(probe(tmp_path, 63, "SCOPE", play), False)


def test_063_harmless_preflight_does_not_need_serial(tmp_path):
    play = scope_play()
    play.insert(0, {"hosts": "fleet", "tasks": [{"debug": {"msg": "preflight"}}]})
    expect(probe(tmp_path, 63, "SCOPE", play), True)


@pytest.mark.parametrize(
    "bypass",
    [
        "rescue",
        "always",
        "ignore_play",
        "ignore_block",
        "archive_command",
        "forged_fact",
    ],
)
def test_096_integrity_failure_cannot_be_swallowed_or_invalidated(tmp_path, bypass):
    digest, play = integrity_play()
    tasks = play[0]["tasks"]
    if bypass in ("rescue", "always"):
        play[0]["tasks"] = [
            tasks[0],
            {"block": [tasks[1]], bypass: [{"debug": {"msg": "continue"}}]},
            tasks[2],
        ]
    elif bypass == "ignore_play":
        play[0]["ignore_errors"] = True
    elif bypass == "ignore_block":
        play[0]["tasks"] = [
            tasks[0],
            {"block": [tasks[1]], "ignore_errors": True},
            tasks[2],
        ]
    elif bypass == "archive_command":
        tasks.insert(
            2,
            {
                "command": {"argv": ["cp", "other.tar", "recovery.tar"]},
                "delegate_to": "localhost",
            },
        )
    else:
        tasks.insert(1, {"set_fact": {"artifact": {"stat": {"checksum": digest}}}})
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


def test_046_unselected_deployment_reporting_does_not_mutate_inspection(tmp_path):
    play = [
        {
            "hosts": "fleet",
            "tasks": [
                {
                    "copy": {"dest": "/srv/site/banner.txt", "content": "north-46"},
                    "tags": "deploy",
                    "changed_when": False,
                },
                {"stat": {"path": "/srv/site/banner.txt"}, "tags": "inspect"},
            ],
        }
    ]
    expect(probe(tmp_path, 46, "TAGS", play), True)


def test_096_explicit_false_ignore_errors_and_read_only_preflight_are_equivalent(
    tmp_path,
):
    digest, play = integrity_play()
    play[0]["ignore_errors"] = False
    play.insert(
        0,
        {
            "hosts": "fleet",
            "ignore_errors": False,
            "tasks": [{"debug": {"msg": "preflight"}}],
        },
    )
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), True)
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    result = subprocess.run(
        [sys.executable, "-"],
        input=program(96, "VERIFY", 1),
        cwd=tmp_path,
        env=check_environment(tmp_path),
        capture_output=True,
        text=True,
    )
    expect(result, True)


def test_096_target_write_before_verification_is_rejected(tmp_path):
    digest, play = integrity_play()
    play[0]["tasks"].insert(
        0,
        {"copy": {"dest": "/srv/site/message", "content": "north-96", "mode": "0644"}},
    )
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


def test_096_spaced_side_effect_lookup_cannot_mutate_archive(tmp_path):
    digest, play = integrity_play()
    play[0]["tasks"].insert(
        2, {"debug": {"msg": "{{ lookup  ('pipe', 'cp other.tar recovery.tar') }}"}}
    )
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


def test_028_parallel_role_delivery_is_not_hidden_by_visible_task_trace(tmp_path):
    label = "Visible serial delivery"
    play = [
        {"hosts": "fleet", "roles": ["unchecked_delivery"]},
        {
            "hosts": "fleet",
            "serial": 1,
            "tasks": [
                {
                    "name": label,
                    "copy": {
                        "dest": "/srv/site/message",
                        "content": "north-ready",
                        "mode": "0644",
                    },
                }
            ],
        },
    ]
    role = tmp_path / "roles/unchecked_delivery/tasks/main.yml"
    role.parent.mkdir(parents=True)
    role.write_text(
        yaml.safe_dump(
            [
                {
                    "copy": {
                        "dest": "/srv/site/message",
                        "content": "unverified",
                        "mode": "0644",
                    }
                }
            ]
        )
    )
    trace = (
        "\n".join(
            json.dumps({"task": "unchecked_delivery : copy", "host": host})
            for host in ("app2", "app1", "app3")
        )
        + "\n"
        + "\n".join(
            json.dumps({"task": label, "host": host})
            for host in ("app1", "app2", "app3")
        )
    )
    expect(probe(tmp_path, 28, "CHECK", play, {"rollout-events.jsonl": trace}), False)


def test_096_role_cannot_restore_before_the_visible_checksum_guard(tmp_path):
    digest, play = integrity_play()
    play[0]["roles"] = ["unchecked_restore"]
    role = tmp_path / "roles/unchecked_restore/tasks/main.yml"
    role.parent.mkdir(parents=True)
    role.write_text(
        yaml.safe_dump(
            [
                {
                    "ansible.builtin.unarchive": {
                        "src": "recovery.tar",
                        "dest": "/srv/site",
                    }
                }
            ]
        )
    )
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


def test_096_forced_handlers_cannot_bypass_checksum_failure(tmp_path):
    digest, play = integrity_play()
    play[0]["force_handlers"] = True
    play[0]["pre_tasks"] = [
        {
            "debug": {"msg": "preflight"},
            "changed_when": True,
            "notify": "Unverified restore",
        }
    ]
    play[0]["handlers"].append(
        {
            "name": "Unverified restore",
            "ansible.builtin.unarchive": {"src": "recovery.tar", "dest": "/srv/site"},
        }
    )
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


@pytest.mark.parametrize(
    "count,serial,good",
    [
        (3, "33%", True),
        (7, "33%", False),
        (7, "14%", True),
        (3, [1, 1, "100%"], True),
        (3, "33.3%", False),
        (3, True, False),
    ],
)
def test_063_percentage_effect_uses_actual_inventory_and_remaining_hosts(
    tmp_path, count, serial, good
):
    play = scope_play()
    play[0]["serial"] = serial
    (tmp_path / "inventory.json").write_text(
        json.dumps(
            {
                "_meta": {"hostvars": {}},
                "all": {"children": ["fleet"]},
                "fleet": {"hosts": ["app" + str(i) for i in range(1, count + 1)]},
            }
        )
    )
    expect(probe(tmp_path, 63, "SCOPE", play), good)


def test_046_foreign_collection_is_not_a_read_only_builtin(tmp_path):
    module = (
        tmp_path
        / "collections/ansible_collections/foreign/check/plugins/modules/stat.py"
    )
    module.parent.mkdir(parents=True)
    module.write_text(
        "from ansible.module_utils.basic import AnsibleModule\nfrom pathlib import Path\nm=AnsibleModule(argument_spec={'path':{'type':'path'}},supports_check_mode=True)\nPath('/tmp/hidden-inspection-write').write_text('changed')\nm.exit_json(changed=False,stat={'exists':True})\n"
    )
    play = [
        {
            "hosts": "fleet",
            "tasks": [
                {
                    "copy": {"dest": "/srv/site/banner.txt", "content": "north-46"},
                    "tags": "deploy",
                },
                {
                    "foreign.check.stat": {"path": "/srv/site/banner.txt"},
                    "tags": "inspect",
                },
            ],
        }
    ]
    expect(probe(tmp_path, 46, "TAGS", play), False)


@pytest.mark.parametrize(
    "bypass",
    [
        "post_guard_handler",
        "handler_chain",
        "never_guard",
        "facts_override",
        "vars_file",
    ],
)
def test_096_declared_execution_edges_cannot_bypass_integrity(tmp_path, bypass):
    digest, play = integrity_play()
    task = play[0]["tasks"]
    stat, guard, extract = task
    if bypass == "post_guard_handler":
        play = [
            {
                "hosts": "fleet",
                "vars": {"expected_sha256": digest},
                "pre_tasks": [stat, guard],
                "tasks": [
                    {
                        "debug": {"msg": "verified"},
                        "changed_when": True,
                        "notify": "Replace archive",
                    }
                ],
                "handlers": [
                    {
                        "name": "Replace archive",
                        "copy": {
                            "src": "other.tar",
                            "dest": "{{ playbook_dir }}/recovery.tar",
                        },
                    }
                ],
            },
            {
                "hosts": "fleet",
                "serial": 1,
                "handlers": [reload("Reload station")],
                "tasks": [extract],
            },
        ]
    elif bypass == "handler_chain":
        play[0]["handlers"][0]["notify"] = "Replace archive"
        play[0]["handlers"].append(
            {
                "name": "Replace archive",
                "copy": {"src": "other.tar", "dest": "{{ playbook_dir }}/recovery.tar"},
            }
        )
    elif bypass == "never_guard":
        guard["tags"] = "never"
    elif bypass == "facts_override":
        task.insert(0, {"set_fact": {"expected_sha256": "f" * 64}})
    else:
        play[0]["vars_files"] = ["overrides.yml"]
        (tmp_path / "overrides.yml").write_text(
            yaml.safe_dump({"expected_sha256": "f" * 64})
        )
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Qualified Ansible inventory CLI is in the workstation",
)
@pytest.mark.parametrize(
    "count,serial,good",
    [
        (3, "33%", True),
        (7, "33%", False),
        (7, "14%", True),
        (3, [1, 1, "100%"], True),
        (3, "33.3%", False),
        (3, True, False),
    ],
)
def test_063_real_inventory_cli_percentage_semantics(tmp_path, count, serial, good):
    image = os.environ.get("DQ_ANSIBLE_TEST_IMAGE")
    assert image
    play = scope_play()
    play[0]["serial"] = serial
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    (tmp_path / "ansible.cfg").write_text("[defaults]\ninventory=inventory.ini\n")
    (tmp_path / "inventory.ini").write_text(
        "[fleet]\n"
        + "".join(
            f"app{i} ansible_host=app{(i - 1) % 3 + 1}\n" for i in range(1, count + 1)
        )
    )
    result = subprocess.run(
        [
            "docker",
            "--host",
            "unix:///var/run/docker.sock",
            "run",
            "--rm",
            "--entrypoint",
            "python3",
            "--mount",
            f"type=bind,src={tmp_path},dst=/proof,readonly",
            "--workdir",
            "/proof",
            image,
            "-I",
            "-c",
            program(63, "SCOPE"),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    expect(result, good)


def test_096_module_defaults_cannot_switch_to_an_unverified_remote_archive(tmp_path):
    digest, play = integrity_play()
    play[0]["module_defaults"] = {"ansible.builtin.unarchive": {"remote_src": True}}
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


def test_096_handler_alias_respects_the_play_collection_order(tmp_path):
    digest, play = integrity_play()
    play[0]["collections"] = ["foreign.check"]
    expect(probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}), False)


@pytest.mark.skipif(
    os.environ.get("DQ_INTEGRATION") != "1",
    reason="Qualified configured inventory CLI is in the workstation",
)
def test_063_real_inventory_follows_the_playbook_configuration(tmp_path):
    image = os.environ.get("DQ_ANSIBLE_TEST_IMAGE")
    assert image
    play = scope_play()
    play[0]["serial"] = "33%"
    (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
    (tmp_path / "inventory.ini").write_text("[fleet]\napp1\napp2\napp3\n")
    (tmp_path / "actual.ini").write_text(
        "[fleet]\n" + "".join(f"app{i}\n" for i in range(1, 8))
    )
    (tmp_path / "ansible.cfg").write_text("[defaults]\ninventory=actual.ini\n")
    result = subprocess.run(
        [
            "docker",
            "--host",
            "unix:///var/run/docker.sock",
            "run",
            "--rm",
            "--entrypoint",
            "python3",
            "--mount",
            f"type=bind,src={tmp_path},dst=/proof,readonly",
            "--workdir",
            "/proof",
            image,
            "-I",
            "-c",
            program(63, "SCOPE"),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    expect(result, False)


@pytest.mark.parametrize("binding", ["unrelated_register", "rebound_register"])
def test_096_checksum_guard_uses_the_current_register_binding(tmp_path, binding):
    digest, play = integrity_play()
    play[0]["tasks"].insert(
        1,
        {
            "stat": {
                "path": "{{ playbook_dir }}/other.tar",
                "checksum_algorithm": "sha256",
            },
            "delegate_to": "localhost",
            "register": "artifact" if binding == "rebound_register" else "unrelated",
        },
    )
    expect(
        probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}),
        binding == "unrelated_register",
    )


@pytest.mark.parametrize(
    "layout", ["root", "trusted_shadow", "wrong_shadow", "absolute_source"]
)
def test_096_unarchive_search_must_select_the_trusted_archive(tmp_path, layout):
    import hashlib

    digest, play = integrity_play()
    contents = b"trusted controller archive bytes"
    digest = hashlib.sha256(contents).hexdigest()
    play[0]["vars"]["expected_sha256"] = digest
    (tmp_path / "recovery.tar").write_bytes(contents)
    if layout != "root":
        (tmp_path / "files").mkdir()
        (tmp_path / "files/recovery.tar").write_bytes(
            contents if layout == "trusted_shadow" else b"untrusted replacement archive"
        )
    if layout == "absolute_source":
        play[0]["tasks"][2]["ansible.builtin.unarchive"]["src"] = (
            "{{ playbook_dir }}/recovery.tar"
        )
    expect(
        probe(tmp_path, 96, "VERIFY", play, {"trusted.sha256": digest}),
        layout != "wrong_shadow",
    )


@pytest.mark.parametrize(
    "quest,tag,shadow", [(25, "DQ_RECAP", "json"), (96, "VERIFY", "yaml")]
)
@pytest.mark.parametrize("good", [True, False])
def test_actual_checker_entrypoint_isolates_working_directory_modules(
    tmp_path, quest, tag, shadow, good
):
    # Keep the production interpreter flags and stdin/shell entrypoint. Only use
    # this test environment's executable and fixture-owned receipt/log paths.
    import shlex

    source = (ROOT / f"quests/{quest:03}/check-0.sh").read_text()
    command = re.search(
        r"(?m)^python3[^\n]* <<'"
        + re.escape(tag)
        + r"'\n.*?\n"
        + re.escape(tag)
        + r"(?=\n|$)",
        source,
        re.S,
    )[0]
    if quest == 25:
        log = tmp_path / "recaps.log"
        log.write_text(
            "PLAY RECAP ***\n"
            + "\n".join(
                f"app{i} : changed={0 if good or i != 2 else 1} failed=0 unreachable=0"
                for i in (1, 2, 3)
            )
        )
        command = command.replace("/tmp/idempotence-second.log", str(log))
    else:
        digest, play = integrity_play()
        if not good:
            play[0]["tasks"][1]["ansible.builtin.assert"]["that"] = [
                "expected_sha256 == expected_sha256"
            ]
        (tmp_path / "rollout.yml").write_text(yaml.safe_dump(play))
        receipt = tmp_path / "trusted.sha256"
        receipt.write_text(digest)
        command = command.replace("/run/dq/facts/0/artifact.sha256", str(receipt))
    (tmp_path / (shadow + ".py")).write_text("raise SystemExit(0)\n")
    command = command.replace("python3", shlex.quote(sys.executable), 1)
    result = subprocess.run(
        ["bash", "-euc", command],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        timeout=10,
    )
    expect(result, good)
