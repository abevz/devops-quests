"""Exercise result predicates with actual Git values and narrow policy documents."""
import json
import os
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT


def goal(number, index=0):
    return yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())["stages"][0]["objectives"][index]["check"]


def inline(number, marker):
    return goal(number).split("<<'" + marker + "'\n", 1)[1].split("\n" + marker, 1)[0]


@pytest.mark.parametrize("notice,good", [(b"north-41\n", True), (b"north-41\r\n", True), (b"north-410\n", False), (b"south-41\n", False)])
def test_041_notice_value_accepts_equivalent_line_endings(tmp_path, notice, good):
    workspace = tmp_path / "quest"
    workspace.mkdir()
    repo = workspace / "repository"
    origin = tmp_path / "origin.git"
    subprocess.run(["git", "init", "--bare", "--initial-branch=main", str(origin)], check=True, capture_output=True)
    subprocess.run(["git", "init", "--initial-branch=main", str(repo)], check=True, capture_output=True)
    (repo / "notice.txt").write_bytes(notice)
    subprocess.run(["git", "-C", str(repo), "add", "notice.txt"], check=True)
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "Notice"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(repo), "remote", "add", "origin", str(origin)], check=True)
    subprocess.run(["git", "-C", str(repo), "push", "-u", "origin", "main"], check=True, capture_output=True)
    (workspace / "platform.env").write_text("")
    result = subprocess.run(["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + goal(41, 2)], env={**os.environ, "HOME": str(tmp_path)}, capture_output=True, timeout=10)
    assert (result.returncode == 0) is good, result.stdout + result.stderr


@pytest.mark.parametrize("representation", ["hcl", "json", "duplicate_read", "narrow_parameters", "write", "extra_path", "wildcard", "legacy_write", "duplicate_json"])
def test_044_policy_equivalence_keeps_only_read_access(tmp_path, representation):
    value = {"path": {"secret/data/dispatch": {"capabilities": ["read"]}}}
    if representation == "write":
        value["path"]["secret/data/dispatch"]["capabilities"].append("update")
    if representation == "extra_path":
        value["path"]["secret/data/other"] = {"capabilities": ["read"]}
    if representation == "wildcard":
        value["path"]["secret/data/*"] = value["path"].pop("secret/data/dispatch")
    if representation == "legacy_write":
        value["path"]["secret/data/dispatch"]["policy"] = "write"
    if representation == "narrow_parameters":
        value["path"]["secret/data/dispatch"]["denied_parameters"] = {"unexpected": []}
    if representation == "duplicate_read":
        value["path"]["secret/data/dispatch"]["capabilities"].append("read")
    text = json.dumps(value)
    if representation == "hcl":
        text = 'path "secret/data/dispatch" { capabilities = ["read"] }\n'
    if representation == "duplicate_json":
        text = '{"path":{"secret/data/*":{"capabilities":["update"]}},"path":{"secret/data/dispatch":{"capabilities":["read"]}}}'
    (tmp_path / "observed-reader.hcl").write_text(text)
    result = subprocess.run([sys.executable, "-"], input=inline(44, "ACL_SCOPE"), cwd=tmp_path, capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is (representation in {"hcl", "json", "duplicate_read", "narrow_parameters"}), result.stderr


@pytest.mark.parametrize("selection,good", [(["old"], True), (["old", "old"], True), (["old", "current"], False), (["current"], False), ([], False), ("old", False)])
def test_066_only_the_obsolete_release_is_selected(tmp_path, selection, good):
    catalog = tmp_path / "catalog.json"
    catalog.write_text(json.dumps({"obsolete": "old", "current": "current", "rollback": "previous"}))
    (tmp_path / "retention.json").write_text(json.dumps({"delete": selection, "note": "unrelated metadata"}))
    code = goal(66).replace("/run/dq/facts/0/release-catalog.json", str(catalog))
    result = subprocess.run(["bash", "-c", code], cwd=tmp_path, capture_output=True, timeout=5)
    assert (result.returncode == 0) is good, result.stderr

def private_documents():
    image = "registry.invalid:5000/parcel@sha256:" + "a" * 64
    worker = {"name": "worker", "image": image, "imagePullPolicy": "Always"}
    deployment = {"metadata": {"uid": "deployment-current"}, "spec": {"template": {"spec": {"containers": [dict(worker)]}}}}
    replicasets = {"items": [{"metadata": {"uid": "rs-current", "ownerReferences": [{"kind": "Deployment", "uid": "deployment-current", "controller": True}]}}]}
    pod = {"metadata": {"uid": "pod-current", "ownerReferences": [{"kind": "ReplicaSet", "uid": "rs-current", "controller": True}]}, "spec": {"containers": [dict(worker)], "imagePullSecrets": [{"name": "registry-pull"}]}, "status": {"phase": "Running", "containerStatuses": [{"name": "worker", "ready": True, "state": {"running": {}}, "imageID": "docker-pullable://" + image}]}}
    return image, deployment, replicasets, {"items": [pod]}


def credential_document(form="auth"):
    import base64

    entry = {"auth": base64.b64encode(b"fixture-user:synthetic-test-value").decode()}
    if form == "fields":
        entry = {"username": "fixture-user", "password": "synthetic-test-value", "email": "fixture@example.invalid"}
    if form == "newlines":
        entry["auth"] = entry["auth"][:8] + "\r\n" + entry["auth"][8:]
    if form == "wrong":
        entry["auth"] = base64.b64encode(b"different-user:synthetic-test-value").decode()
    if form == "precedence":
        entry.update(username="different-user", password="different-value")
    config = {"auths": {"registry.invalid:5000": entry}, "unrelated": {"metadata": True}}
    kind, key = "kubernetes.io/dockerconfigjson", ".dockerconfigjson"
    if form == "legacy":
        kind, key = "kubernetes.io/dockercfg", ".dockercfg"
        config = config["auths"]
    secret = {"type": kind, "data": {key: base64.b64encode(json.dumps(config).encode()).decode()}, "metadata": {"name": "registry-pull", "annotations": {"unrelated": "allowed"}}}
    if form == "malformed":
        secret["data"][key] = "not base64"
    if form == "opaque":
        secret["type"] = "Opaque"
    return secret


def fake_kubectl(tmp_path, configuration):
    path = tmp_path / "fixture-bin"
    path.mkdir(exist_ok=True)
    data = tmp_path / "fixture-kubernetes.json"
    data.write_text(json.dumps(configuration))
    script = """import json,os,sys
config=json.load(open(os.environ['FIXTURE_KUBE']))
args=sys.argv[1:]
if args[:2]==['rollout','status']:
 print('rollout complete');raise SystemExit(1 if config.get('rollout_failed') else 0)
if args[0]=='exec':
 print(config.get('runtime_env','PATH=/bin') if args[-1]=='env' else config['http']);raise SystemExit(0)
if args[:2]==['get','deployment']:value=config['deployment']
elif args[:2]==['get','replicasets']:value=config['replicasets']
elif args[:2]==['get','pods']:value=config['pods']
elif args[:2]==['get','secret']:
 value=config.get('secrets',{}).get(args[2])
 if value is None:raise SystemExit(1)
else:raise SystemExit(2)
print(json.dumps(value))
"""
    (path / "kubectl").write_text("#!" + sys.executable + "\n" + script)
    (path / "kubectl").chmod(0o755)
    return {**os.environ, "PATH": str(path) + os.pathsep + os.environ["PATH"], "FIXTURE_KUBE": str(data)}


def private_program(number, index, mode, stage=0):
    code = yaml.safe_load((ROOT / f"quests/{number:03}/quest.yaml").read_text())["stages"][stage]["objectives"][index]["check"]
    tag = "DQ_PRIVATE_" + mode.upper()
    return code.split("<<'" + tag + "'\n", 1)[1].split("\n" + tag, 1)[0]


@pytest.mark.parametrize("mode,number,index,stage", [("declared_only", 42, 0, 0), ("image", 49, 0, 0), ("only_auth", 49, 1, 0), ("image_policy", 78, 0, 1), ("image", 91, 5, 0), ("image_policy", 99, 4, 0), ("pull", 27, 0, 0)])
@pytest.mark.parametrize("case", ["reference", "observer_first", "unrelated_metadata", "wrong_worker_image", "wrong_worker_policy", "only_observer_digest", "wrong_owner", "extra_secret", "repeated_same_secret"])
def test_private_consumer_is_selected_by_name_and_ownership(tmp_path, mode, number, index, stage, case):
    image, deployment, replicasets, pods = private_documents()
    pod = pods["items"][0]
    if case == "observer_first":
        observer = {"name": "observer", "image": "unrelated.invalid/observer:current", "imagePullPolicy": "Never"}
        deployment["spec"]["template"]["spec"]["containers"].insert(0, observer)
        pod["spec"]["containers"].insert(0, observer)
        pod["status"]["containerStatuses"].insert(0, {"name": "observer", "ready": True, "state": {"running": {}}, "imageID": "sha256:" + "b" * 64})
    if case == "unrelated_metadata":
        deployment["metadata"]["annotations"] = {"unrelated": "allowed"}
    if case == "wrong_worker_image":
        deployment["spec"]["template"]["spec"]["containers"][0]["image"] = "different.invalid/image:wrong"
        pod["spec"]["containers"][0]["image"] = "different.invalid/image:wrong"
    if case == "wrong_worker_policy":
        deployment["spec"]["template"]["spec"]["containers"][0]["imagePullPolicy"] = "IfNotPresent"
        pod["spec"]["containers"][0]["imagePullPolicy"] = "IfNotPresent"
    if case == "only_observer_digest":
        pod["status"]["containerStatuses"][0]["imageID"] = "containerd://sha256:" + "b" * 64
        pod["status"]["containerStatuses"].append({"name": "observer", "ready": True, "state": {"running": {}}, "imageID": image})
    if case == "wrong_owner":
        pod["metadata"]["ownerReferences"][0]["uid"] = "unrelated-rs"
    if case == "extra_secret":
        pod["spec"]["imagePullSecrets"].append({"name": "unrelated-pull"})
    if case == "repeated_same_secret":
        pod["spec"]["imagePullSecrets"].append({"name": "registry-pull"})
    config = {"deployment": deployment, "replicasets": replicasets, "pods": pods, "secrets": {"registry-pull": credential_document(), "unrelated-pull": {"type": "Opaque"}}}
    environment = fake_kubectl(tmp_path, config)
    result = subprocess.run([sys.executable, "-", json.dumps(deployment), json.dumps(replicasets), json.dumps(pods), image, "registry.invalid:5000", "fixture-user", "synthetic-test-value"], input=private_program(number, index, mode, stage), cwd=tmp_path, env=environment, capture_output=True, text=True, timeout=10)
    wrong = case == "wrong_owner" or (case == "wrong_worker_image" and mode != "only_auth") or (case == "wrong_worker_policy" and mode != "image") or (case == "only_observer_digest" and mode in {"image", "image_policy", "pull"}) or (case == "extra_secret" and mode in {"declared_only", "only_auth"})
    assert (result.returncode == 0) is (not wrong), result.stdout + result.stderr


@pytest.mark.parametrize("form,good", [("auth", True), ("fields", True), ("newlines", True), ("legacy", True), ("precedence", True), ("wrong", False), ("malformed", False), ("opaque", False)])
def test_042_registry_credentials_accept_usable_auth_forms(tmp_path, form, good):
    code = goal(42, 2).split("<<'DQ_REGISTRY_CREDENTIALS'\n", 1)[1].split("\nDQ_REGISTRY_CREDENTIALS", 1)[0]
    result = subprocess.run([sys.executable, "-", json.dumps(credential_document(form)), "registry.invalid:5000", "fixture-user", "synthetic-test-value"], input=code, cwd=tmp_path, capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is good, result.stdout + result.stderr


def test_042_real_shell_handles_large_unrelated_metadata_and_local_helpers(tmp_path):
    image, deployment, replicasets, pods = private_documents()
    deployment["metadata"]["annotations"] = {"unrelated": "x" * 180000}
    workspace = tmp_path / "quest"
    workspace.mkdir()
    (workspace / "platform.env").write_text("export PRIVATE_IMAGE='" + image + "'\nexport REGISTRY=registry.invalid:5000\nexport REGISTRY_USER=fixture-user\nexport REGISTRY_PASSWORD=synthetic-test-value\n")
    (workspace / "json.py").write_text("raise RuntimeError('a player helper must not replace the checker module')\n")
    environment = fake_kubectl(tmp_path, {"deployment": deployment, "replicasets": replicasets, "pods": pods})
    result = subprocess.run(["bash", "-c", "set -euo pipefail\ncd ~/quest\n" + goal(42)], env={**environment, "HOME": str(tmp_path)}, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stdout + result.stderr


def run_jq_clause(code, document, environment=()):
    import shlex

    line = next(line for line in code.splitlines() if 'jq -e ' in line)
    arguments = shlex.split(line.split('jq ', 1)[1])
    values = dict(environment)
    arguments = [values.get(value, value) for value in arguments if value not in {'>/dev/null', 'provenance.json'}]
    return subprocess.run(['jq', *arguments], input=json.dumps(document), capture_output=True, text=True, timeout=5).returncode == 0


@pytest.mark.parametrize('number,index', [(43, 0), (61, 2), (68, 0), (75, 2), (91, 1), (95, 1), (99, 1)])
@pytest.mark.parametrize('path,good', [('manifests', True), ('./manifests/', True), ('manifests/./', True), ('other', False), ('../manifests', False), ('/manifests', False), ('manifests/../other', False)])
def test_private_git_workload_directory_keeps_same_relative_content(number, index, path, good):
    document = {'spec': {'source': {'repoURL': 'fixture://private', 'path': path, 'targetRevision': 'main'}, 'project': 'station', 'destination': {'namespace': 'bay-fixture', 'server': 'https://kubernetes.default.svc'}}}
    assert run_jq_clause(goal(number, index), document, [('$GIT_URL', 'fixture://private'), ('$url', 'fixture://private'), ('$DQ_NAMESPACE', 'bay-fixture'), ('$(cat release-commit)', 'fixture-commit')]) is good


@pytest.mark.parametrize('destination,good', [({'server': 'https://kubernetes.default.svc'}, True), ({'name': 'in-cluster'}, True), ({'name': 'in-cluster', 'server': 'https://kubernetes.default.svc'}, False), ({'name': 'different'}, False), ({'server': 'https://unrelated.invalid'}, False)])
def test_043_destination_identifies_only_the_provided_local_cluster(destination, good):
    document = {'spec': {'source': {'repoURL': 'fixture://private', 'path': 'manifests', 'targetRevision': 'main'}, 'project': 'station', 'destination': dict(destination, namespace='bay-fixture')}}
    assert run_jq_clause(goal(43), document, [('$GIT_URL', 'fixture://private'), ('$DQ_NAMESPACE', 'bay-fixture')]) is good


@pytest.mark.parametrize('number,index,variable', [(48, 4, 'ROUTE'), (99, 5, 'ROUTE_SECRET')])
@pytest.mark.parametrize('case,good', [('reference', True), ('unrelated_env', True), ('optional', True), ('observer_first', True), ('wrong_key', False), ('wrong_secret', False), ('literal', False), ('last_wrong', False), ('last_right', True), ('token_reference', False), ('literal_token', False)])
def test_secret_consumer_checks_the_effective_named_reference(tmp_path, number, index, variable, case, good):
    import shlex

    entry = {'name': variable, 'valueFrom': {'secretKeyRef': {'name': 'route-secret', 'key': 'value'}}}
    worker = {'name': 'worker', 'env': [entry]}
    deployment = {'spec': {'template': {'spec': {'containers': [worker]}}}}
    if case == 'unrelated_env':
        worker['env'].insert(0, {'name': 'UNRELATED', 'value': 'allowed'})
    if case == 'optional':
        entry['valueFrom']['secretKeyRef']['optional'] = False
    if case == 'observer_first':
        deployment['spec']['template']['spec']['containers'].insert(0, {'name': 'observer', 'env': []})
    if case == 'wrong_key':
        entry['valueFrom']['secretKeyRef']['key'] = 'different'
    if case == 'wrong_secret':
        entry['valueFrom']['secretKeyRef']['name'] = 'different'
    if case == 'literal':
        entry.pop('valueFrom')
        entry['value'] = 'north-secret'
    if case == 'last_wrong':
        worker['env'].append({'name': variable, 'value': 'wrong'})
    if case == 'last_right':
        worker['env'].insert(0, {'name': variable, 'value': 'overridden'})
    if case == 'token_reference':
        worker['env'].append({'name': 'VAULT_TOKEN', 'valueFrom': {'secretKeyRef': {'name': 'workstation-token-copy', 'key': 'token'}}})
        good = number != 48
    if case == 'literal_token':
        worker['env'].append({'name': 'VAULT_TOKEN', 'value': 'private-fixture-token'})
        good = number != 48
    _, original, replicasets, pods = private_documents()
    deployment['metadata'] = original['metadata']
    pods['items'][0]['metadata']['name'] = 'pod-current'
    environment = fake_kubectl(tmp_path, {'deployment': deployment, 'replicasets': replicasets, 'pods': pods, 'runtime_env': 'PATH=/bin\nVAULT_TOKEN=private-fixture-token' if case == 'token_reference' else 'PATH=/bin\nUNRELATED=allowed'})
    arguments = shlex.split(goal(number, index).split('python3 -I -c ', 1)[1])
    result = subprocess.run([sys.executable, '-I', '-c', arguments[0]], input=json.dumps(deployment), env={**environment, 'DQ_CHECK_TOKEN': 'private-fixture-token'}, capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is good, result.stderr


def healthy_board():
    code = (ROOT / 'quests/095/setup-0.sh').read_text().split("cat > repository/manifests/board.yaml <<'DQ_ASSET'\n", 1)[1].split('\nDQ_ASSET', 1)[0]
    return yaml.safe_load(code.replace('__DQ_APP_IMAGE__', 'fixture.invalid/app:provided'))


@pytest.mark.parametrize('number', [68, 95])
@pytest.mark.parametrize('case,good', [('reference', True), ('format_and_metadata', True), ('observer_first', True), ('quantity_units', True), ('equivalent_process', True), ('named_port', True), ('different_live_probe', False), ('uncommitted_process', False), ('wrong_http', False), ('rollout_failed', False), ('missing_worker', False), ('wrong_image', False), ('wrong_profile', False), ('wrong_resources', False), ('new_bad_liveness', False), ('new_bad_startup', False), ('uncommitted_liveness', False), ('uncommitted_startup', False)])
def test_git_health_uses_semantic_configuration_and_observed_consumer(tmp_path, number, case, good):
    import copy

    reference = healthy_board()
    desired = copy.deepcopy(reference)
    container = desired['spec']['template']['spec']['containers'][0]
    if number == 68:
        container['readinessProbe'] = {'httpGet': {'path': '/', 'port': 8080}}
    if case == 'format_and_metadata':
        desired['metadata']['annotations'] = {'fixture.example/note': 'harmless metadata'}
    if case == 'observer_first':
        observer = copy.deepcopy(container)
        observer.update(name='observer', command=['sh', '-c', 'sleep 3600'])
        observer.pop('readinessProbe', None)
        desired['spec']['template']['spec']['containers'].insert(0, observer)
    if case == 'quantity_units':
        container['resources']['requests'].update(cpu='0.01', memory='8192Ki')
        container['resources']['limits'].update(cpu='0.2', memory='33554432')
    if case == 'equivalent_process':
        container['command'][-1] = ':; ' + container['command'][-1]
    if case == 'named_port':
        container['ports'] = [{'name': 'http', 'containerPort': 8080}]
        container['readinessProbe'] = {'httpGet': {'path': '/', 'port': 'http'}}
    if case == 'missing_worker':
        container['name'] = 'unrelated'
    if case == 'wrong_image':
        container['image'] = 'fixture.invalid/unapproved:wrong'
        good = number == 68
    if case == 'wrong_profile':
        container['securityContext']['allowPrivilegeEscalation'] = True
        good = number == 68
    if case == 'wrong_resources':
        container['resources']['requests']['cpu'] = '100m'
        good = number == 68
    if case in {'new_bad_liveness', 'new_bad_startup'}:
        field = 'livenessProbe' if case == 'new_bad_liveness' else 'startupProbe'
        container[field] = {'httpGet': {'port': 8099}, 'initialDelaySeconds': 300}
        good = number == 68
    live = copy.deepcopy(desired)
    live_worker = live['spec']['template']['spec']['containers'][-1 if case == 'observer_first' else 0]
    if case in {'uncommitted_liveness', 'uncommitted_startup'}:
        field = 'livenessProbe' if case == 'uncommitted_liveness' else 'startupProbe'
        live_worker[field] = {'httpGet': {'port': 8099}, 'initialDelaySeconds': 300}
    if case == 'different_live_probe':
        live_worker['readinessProbe'] = {'httpGet': {'port': 9090}}
    if case == 'uncommitted_process':
        live_worker['command'] = ['sh', '-c', 'a different process']
    repository = tmp_path / 'repository'
    repository.mkdir()
    subprocess.run(['git', 'init', '--initial-branch=main', str(repository)], check=True, capture_output=True)
    manifest = repository / 'manifests/board.yaml'
    manifest.parent.mkdir()
    def commit(value, label):
        manifest.write_text('# YAML formatting is not a workload property\n' + yaml.safe_dump(value, sort_keys=False))
        subprocess.run(['git', '-C', str(repository), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(repository), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-m', label], check=True, capture_output=True)
        return subprocess.check_output(['git', '-C', str(repository), 'rev-parse', 'HEAD'], text=True).strip()
    healthy = commit(reference, 'Healthy baseline')
    commit(desired, 'Current desired release')
    subprocess.run(['git', '-C', str(repository), 'update-ref', 'refs/remotes/origin/main', 'HEAD'], check=True)
    frozen = tmp_path / 'healthy-commit'
    frozen.write_text(healthy + '\n')
    configuration = {'deployment': live, 'http': 'wrong' if case == 'wrong_http' else f'north-{number}', 'rollout_failed': case == 'rollout_failed'}
    environment = fake_kubectl(tmp_path, configuration)
    code = goal(number, 5).replace('/run/dq/facts/0/healthy-commit', str(frozen))
    result = subprocess.run(['bash', '-c', code], cwd=tmp_path, env=environment, capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) is good, result.stdout + result.stderr


@pytest.mark.parametrize('url,good', [('http://receiver.invalid/api/webhook', True), ('http://receiver.invalid/api/webhook?', True), ('http://other.invalid/api/webhook', False), ('http://receiver.invalid/api/webhook?extra=1', False), ('https://receiver.invalid/api/webhook', False), ('http://receiver.invalid/api/webhook/extra', False)])
def test_075_equivalent_empty_query_keeps_receiver_identity(url, good):
    import shlex

    code = goal(75)
    clause = next(line for line in code.splitlines() if 'jq -e ' in line)
    arguments = shlex.split(clause.split('| jq ', 1)[1])
    expression = arguments[-2]
    hook = {'active': True, 'type': 'gogs', 'config': {'url': url, 'content_type': 'json'}, 'events': ['push'], 'branch_filter': 'main'}
    result = subprocess.run(['jq', '-e', '--arg', 'url', 'http://receiver.invalid/api/webhook', expression], input=json.dumps(hook), capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is good, result.stderr


@pytest.mark.parametrize('which', ['git', 'live'])
@pytest.mark.parametrize('path,good', [('manifests', True), ('./manifests/', True), ('wrong', False), ('../manifests', False)])
def test_122_both_child_sources_resolve_the_existing_workload_directory(which, path, good):
    import shlex

    marker = '[DQ:child_source]' if which == 'git' else '[DQ:source]'
    clause = next(line for line in goal(122, 1).splitlines() if marker in line)
    expression = shlex.split(clause)[2]
    result = subprocess.run(['jq', '-e', expression], input=json.dumps({'spec': {'source': {'path': path}}}), capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is good, result.stderr


@pytest.mark.parametrize('form,good', [('auth', True), ('fields', True), ('newlines', True), ('legacy', True), ('wrong', False), ('opaque', False)])
def test_042_hint_verifies_supported_credentials_without_printing_them(form, good):
    import re
    import shlex

    text = yaml.safe_load((ROOT / 'quests/042/i18n/en.yaml').read_text())['hints.2.text']
    command = re.search(r'`source platform.env; kubectl get secret registry-pull -o json \| jq -e ([^`]+)`', text)[1]
    expression = shlex.split(command)[0]
    result = subprocess.run(['jq', '-e', expression], input=json.dumps(credential_document(form)), env={**os.environ, 'REGISTRY': 'registry.invalid:5000', 'REGISTRY_USER': 'fixture-user', 'REGISTRY_PASSWORD': 'synthetic-test-value'}, capture_output=True, text=True, timeout=5)
    assert (result.returncode == 0) is good, result.stderr
    assert 'synthetic-test-value' not in result.stdout + result.stderr


@pytest.mark.parametrize('case,good', [('reference', True), ('reordered_keys', True), ('extra_field', False), ('missing_field', False), ('wrong_image', False), ('wrong_commit', False), ('wrong_repo', False)])
def test_091_preserves_the_explicit_exact_three_key_report(case, good):
    report = {'image': 'fixture-image', 'commit': 'fixture-commit', 'repo': 'fixture-repo'}
    if case == 'reordered_keys':
        report = dict(reversed(list(report.items())))
    if case == 'extra_field':
        report['note'] = 'extra metadata is forbidden by this brief'
    if case == 'missing_field':
        report.pop('repo')
    if case.startswith('wrong_'):
        report[case.removeprefix('wrong_')] = 'wrong'
    assert run_jq_clause(goal(91, 5), report, [('$image', 'fixture-image'), ('$commit', 'fixture-commit'), ('$GIT_URL', 'fixture-repo')]) is good


@pytest.mark.parametrize('leak', [None, 'station', 'manager', 'reader'])
def test_048_real_shell_checks_supplied_tokens_even_without_export(tmp_path, leak):
    _, deployment, replicasets, pods = private_documents()
    worker = deployment['spec']['template']['spec']['containers'][0]
    worker['env'] = [{'name': 'ROUTE', 'valueFrom': {'secretKeyRef': {'name': 'route-secret', 'key': 'value'}}}]
    pods['items'][0]['metadata']['name'] = 'reader-current'
    workspace = tmp_path / 'quest'
    workspace.mkdir()
    values = {'station': 'station-fixture-private-value', 'manager': 'manager-fixture-private-value', 'reader': 'reader-fixture-private-value'}
    (workspace / 'station-token').write_text(values['station'] + '\n')
    (workspace / 'platform.env').write_text(f"VAULT_MANAGER_TOKEN='{values['manager']}'\nVAULT_READER_TOKEN='{values['reader']}'\n")
    environment = fake_kubectl(tmp_path, {'deployment': deployment, 'replicasets': replicasets, 'pods': pods, 'http': 'north-secret', 'runtime_env': 'PATH=/bin\nEXTRA=' + (values[leak] if leak else 'harmless')})
    environment = {key: value for key, value in environment.items() if key not in {'VAULT_MANAGER_TOKEN', 'VAULT_READER_TOKEN'}}
    result = subprocess.run(['bash', '-c', 'set -euo pipefail\ncd ~/quest\n' + goal(48, 4)], env={**environment, 'HOME': str(tmp_path)}, capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) is (leak is None), result.stdout + result.stderr
    for value in values.values():
        assert value not in result.stdout + result.stderr


@pytest.mark.parametrize('number', [42, 43, 49, 54, 61, 68, 75, 78, 83, 91, 95, 99, 122])
@pytest.mark.parametrize('layout', ['reference', 'observer_first', 'wrong_worker'])
def test_consumer_readback_targets_the_application_not_a_sidecar(tmp_path, number, layout):
    stage = 1 if number == 78 else 0
    quest = yaml.safe_load((ROOT / f'quests/{number:03}/quest.yaml').read_text())
    code = next(item['check'] for item in quest['stages'][stage]['objectives'] if 'kubectl exec' in item['check'])
    expected = 'north' if number == 54 else 'north-secret' if number == 83 else f'north-{number}'
    target = 'relay' if number in {54, 83} else 'board'
    configuration = {'target': 'deployment/' + target, 'kind': 'environment' if number in {54, 83} else 'http', 'containers': ['worker'] if layout == 'reference' else ['observer', 'worker'], 'worker_value': 'wrong' if layout == 'wrong_worker' else expected, 'observer_value': expected if layout == 'wrong_worker' else 'unrelated'}
    document = tmp_path / 'consumer-fixture.json'
    document.write_text(json.dumps(configuration))
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    script = """import base64,json,os,sys
configuration=json.load(open(os.environ['CONSUMER_FIXTURE']))
args=sys.argv[1:]
if args[:2]==['rollout','status']:
 raise SystemExit(0)
if args[:3]==['get','secret','route-secret']:
 if any(arg.startswith('jsonpath=') for arg in args):
  print(base64.b64encode(b'north-secret').decode(),end='');raise SystemExit(0)
 print(json.dumps({'apiVersion':'v1','kind':'Secret','metadata':{'name':'route-secret'},'type':'Opaque','data':{'value':base64.b64encode(b'north-secret').decode()}}));raise SystemExit(0)
if not args or args[0]!='exec' or configuration['target'] not in args:
 raise SystemExit(1)
selected=args[args.index('-c')+1] if '-c' in args else configuration['containers'][0]
if selected=='observer' and configuration['kind']=='http':
 # A sidecar without wget shares the Pod network but cannot execute this tool.
 raise SystemExit(127)
if selected not in configuration['containers']:
 raise SystemExit(1)
print(configuration[selected+'_value'])
"""
    (binaries / 'kubectl').write_text('#!' + sys.executable + '\n' + script)
    (binaries / 'kubectl').chmod(0o755)
    (binaries / 'curl').write_text('#!' + sys.executable + "\nimport json,sys\nassert sys.argv[-1]=='http://vault.invalid/v1/secret/data/dispatch'\nprint(json.dumps({'data':{'data':{'value':'north-secret'}}}))\n")
    (binaries / 'curl').chmod(0o755)
    workspace = tmp_path / 'quest'
    workspace.mkdir()
    (workspace / 'platform.env').write_text('VAULT_ADDR=http://vault.invalid\nVAULT_READER_TOKEN=synthetic-fixture-token\n')
    result = subprocess.run(['bash', '-c', 'set -euo pipefail\ncd ~/quest\n' + code], env={**os.environ, 'HOME': str(tmp_path), 'PATH': str(binaries) + os.pathsep + os.environ['PATH'], 'CONSUMER_FIXTURE': str(document)}, capture_output=True, text=True, timeout=10)
    assert (result.returncode == 0) is (layout != 'wrong_worker'), result.stdout + result.stderr
    assert 'synthetic-fixture-token' not in result.stdout + result.stderr
