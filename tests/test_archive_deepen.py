"""Archive recovery checks actual bytes and the two production consumer topologies."""

import copy
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

import pytest
import yaml

from devops_quests.catalog import ROOT, Catalog
from devops_quests.runtime import Runtime


def consumer_fixture():
    image = 'registry.test:5000/parcel@sha256:' + 'a' * 64
    worker = {'name': 'worker', 'image': image}
    deployment = {'kind': 'Deployment', 'metadata': {'name': 'archive-web', 'uid': 'web', 'generation': 2}, 'spec': {'replicas': 1, 'template': {'spec': {'containers': [copy.deepcopy(worker)]}}}, 'status': {'readyReplicas': 1, 'observedGeneration': 2}}
    source = copy.deepcopy(deployment)
    template = {'containers': [copy.deepcopy(worker)], 'restartPolicy': 'Never'}
    cron = {'kind': 'CronJob', 'metadata': {'name': 'archive-scan', 'uid': 'cron'}, 'spec': {'suspend': True, 'jobTemplate': {'spec': {'template': {'spec': copy.deepcopy(template)}}}}}
    job = {'kind': 'Job', 'metadata': {'name': 'recovery', 'uid': 'new-job'}, 'spec': {'template': {'spec': copy.deepcopy(template)}}, 'status': {'conditions': [{'type': 'Complete', 'status': 'True'}]}}
    service = {'kind': 'Service', 'metadata': {'name': 'archive-web', 'uid': 'service'}}
    app = {'kind': 'Application', 'metadata': {'name': 'release', 'uid': 'app', 'namespace': 'owned'}, 'spec': {'project': 'station', 'source': {'repoURL': 'http://owned/repo.git', 'path': 'manifests', 'targetRevision': 'main'}, 'destination': {'server': 'https://kubernetes.default.svc', 'namespace': 'owned'}, 'syncPolicy': {'automated': {'prune': True, 'selfHeal': True}}}, 'status': {'sync': {'status': 'Synced', 'revision': 'published-head'}}}
    rs = {'kind': 'ReplicaSet', 'metadata': {'name': 'web-rs', 'uid': 'rs', 'ownerReferences': [{'kind': 'Deployment', 'uid': 'web', 'controller': True}]}}
    web = {'kind': 'Pod', 'metadata': {'name': 'web-pod', 'ownerReferences': [{'kind': 'ReplicaSet', 'uid': 'rs', 'controller': True}]}, 'spec': {'containers': [copy.deepcopy(worker)]}, 'status': {'phase': 'Running', 'containerStatuses': [{'name': 'worker', 'imageID': image, 'ready': True, 'state': {'running': {}}}]}}
    batch = {'kind': 'Pod', 'metadata': {'name': 'batch-pod', 'ownerReferences': [{'kind': 'Job', 'uid': 'new-job', 'controller': True}]}, 'spec': {'containers': [copy.deepcopy(worker)]}, 'status': {'phase': 'Succeeded', 'containerStatuses': [{'name': 'worker', 'imageID': image, 'ready': False, 'state': {'terminated': {'exitCode': 0}}}]}}
    objects = [deployment, cron, job, service, app, rs, web, batch]
    baseline = {'identities': {o['kind'] + '/' + o['metadata']['name']: o['metadata']['uid'] for o in [deployment, cron, service, app]}, 'source': copy.deepcopy(app['spec']['source']), 'previous_jobs': ['old-job'], 'http_response': 'archive-97', 'batch_response': 'checked-97'}
    return image, source, objects, baseline


@pytest.mark.parametrize('case,good,reason', [
    ('reference', True, None), ('tagged_digest', True, None), ('scaled_web', True, None),
    ('stale_job', False, 'batch'), ('fake_complete', False, 'batch'),
    ('foreign_pod', False, 'batch'), ('wrong_batch_image_id', False, 'batch'),
    ('mutable_batch', False, 'batch'), ('different_job_template', False, 'batch'),
    ('unsuspended', False, 'identity'), ('recreated_controller', False, 'identity'),
    ('unpublished_repair', False, 'source'), ('stale_revision', False, 'source'),
    ('wrong_web_image_id', False, 'web'), ('unready_web', False, 'web'),
])
def test_consumer_check_distinguishes_real_topologies(tmp_path, case, good, reason):
    image, source, objects, baseline = consumer_fixture()
    deployment, cron, job, service, app, rs, web, batch = objects
    if case == 'scaled_web':
        deployment['spec']['replicas'] = 2
        deployment['status']['readyReplicas'] = 2
        extra = copy.deepcopy(web)
        extra['metadata']['name'] = 'second-web-pod'
        objects.append(extra)
    if case == 'tagged_digest':
        reference = image.replace('/parcel@', '/parcel:recovered@')
        source['spec']['template']['spec']['containers'][0]['image'] = reference
        deployment['spec']['template']['spec']['containers'][0]['image'] = reference
        web['spec']['containers'][0]['image'] = reference
        for template in [cron['spec']['jobTemplate']['spec']['template']['spec'], job['spec']['template']['spec'], batch['spec']]:
            template['containers'][0]['image'] = reference
    if case == 'stale_job':
        job['metadata']['uid'] = 'old-job'
        batch['metadata']['ownerReferences'][0]['uid'] = 'old-job'
    if case == 'fake_complete':
        batch['status']['phase'] = 'Failed'
        batch['status']['containerStatuses'][0]['state']['terminated']['exitCode'] = 1
    if case == 'foreign_pod':
        batch['metadata']['ownerReferences'][0]['uid'] = 'foreign-job'
    if case == 'wrong_batch_image_id':
        batch['status']['containerStatuses'][0]['imageID'] = image.replace('a' * 64, 'b' * 64)
    if case == 'mutable_batch':
        cron['spec']['jobTemplate']['spec']['template']['spec']['containers'][0]['image'] = 'registry.test:5000/parcel:1'
    if case == 'different_job_template':
        job['spec']['template']['spec']['containers'][0]['command'] = ['false']
    if case == 'unsuspended':
        cron['spec']['suspend'] = False
    if case == 'recreated_controller':
        deployment['metadata']['uid'] = 'replacement'
    if case == 'unpublished_repair':
        source['spec']['template']['spec']['containers'][0]['image'] = 'registry.test:5000/parcel:retired'
    if case == 'stale_revision':
        app['status']['sync']['revision'] = 'older'
    if case == 'wrong_web_image_id':
        web['status']['containerStatuses'][0]['imageID'] = image.replace('a' * 64, 'b' * 64)
    if case == 'unready_web':
        web['status']['containerStatuses'][0]['ready'] = False
    (tmp_path / 'release-image').write_text(image)
    (tmp_path / 'recovery-baseline.json').write_text(json.dumps(baseline))
    kubectl = tmp_path / 'kubectl'
    kubectl.write_text('#!/bin/sh\nif [ "$1" = logs ]; then echo checked-97; else echo archive-97; fi\n')
    kubectl.chmod(0o755)
    quest = yaml.safe_load((ROOT / 'quests/097/quest.yaml').read_text())
    code = quest['stages'][0]['objectives'][1]['check'].split("<<'DQ_RECOVERY_CONSUMERS'\n", 1)[1].split('\nDQ_RECOVERY_CONSUMERS', 1)[0]
    for filename in ['release-image', 'recovery-baseline.json']:
        code = code.replace(repr('/run/dq/facts/0/' + filename), repr(str(tmp_path / filename)))
    result = subprocess.run([sys.executable, '-I', '-', yaml.safe_dump(source), json.dumps({'items': objects}), 'published-head'], input=code, capture_output=True, text=True, timeout=10, env={**os.environ, 'PATH': str(tmp_path) + os.pathsep + os.environ['PATH']})
    assert (result.returncode == 0) is good, result.stdout + result.stderr
    if not good:
        assert '[DQ:recovery_' + reason + ']' in result.stdout


@pytest.mark.skipif(os.environ.get('DQ_INTEGRATION') != '1', reason='Explicit local sandbox opt-in required')
def test_old_archive_fix_and_registry_execution_shortcuts_are_rejected():
    runtime = Runtime(ROOT / '.state/runtime')
    catalog = Catalog()
    run = {'id': secrets.token_hex(12), 'level': 97}
    folder = Path(os.environ.get('DQ_DEEPEN_EVIDENCE', ROOT / 'artifacts/deepen-shortcuts'))
    folder.mkdir(parents=True, exist_ok=True)
    evidence = {'quest': 97, 'run': run['id']}
    check = catalog.script(97, 0, 'check')
    try:
        runtime.create(run)
        runtime.exec(run, catalog.script(97, 0, 'setup'), timeout=240)
        runtime.capture_facts(dict(run, stage=0), catalog.quests[97]['immutable'][0])
        cached = runtime.exec(run, 'cd ~/quest\nsource platform.env\ndocker push "$REGISTRY/parcel:1"\n', check=False)
        assert cached.returncode != 0, 'Original image must not have a usable cached alias'
        old = runtime.exec(run, (ROOT / 'tests/fixtures/deepen-archive/097-old.sh').read_text(), timeout=180)
        assert old.returncode == 0
        producer_only = runtime.exec(run, check, check=False)
        assert producer_only.returncode != 0 and '[DQ:recovery_source]' in producer_only.stdout
        runtime.exec(run, (ROOT / 'solutions/097/0.sh').read_text(), timeout=240)
        assert runtime.exec(run, check, check=False).returncode == 0
        # A mutable alias must fail even with real healthy consumers.
        for mutation, restoration, reason in [
            ('kubectl set image cronjob/archive-scan "worker=$REGISTRY/parcel:1"', 'kubectl set image cronjob/archive-scan "worker=$(cat /run/dq/facts/0/release-image)"', 'batch'),
        ]:
            runtime.exec(run, 'cd ~/quest\nsource platform.env\n' + mutation)
            result = runtime.exec(run, check, check=False)
            assert result.returncode != 0 and '[DQ:recovery_' + reason + ']' in result.stdout
            runtime.exec(run, 'cd ~/quest\nsource platform.env\n' + restoration)
        denied = runtime.exec(run, '''set -euo pipefail
if kubectl create role fake-execution --verb=patch --resource=pods/status,jobs/status; then exit 1; fi
if kubectl patch job interrupted-attempt --subresource=status --type=merge -p '{"status":{"succeeded":1}}'; then exit 1; fi
''', check=False)
        assert denied.returncode == 0
        runtime.exec(run, 'cd ~/quest\ncp recovery-image.tar /tmp/retained-archive.tar\nprintf x >> recovery-image.tar\n')
        archive = runtime.exec(run, 'cd ~/quest\n' + catalog.quests[97]['stages'][0]['objectives'][0]['check'], check=False)
        assert archive.returncode != 0
        runtime.exec(run, 'cd ~/quest\ncp /tmp/retained-archive.tar recovery-image.tar\n')
        # Ready Pods can use a node cache: an actually missing registry layer must still fail.
        runtime.exec(run, '''set -euo pipefail
cd ~/quest
source platform.env
image=$(cat /run/dq/facts/0/release-image)
layer=$(curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' "https://$REGISTRY/v2/parcel/manifests/${image##*@}" | jq -er '.layers[0].digest')
curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -X DELETE "https://$REGISTRY/v2/parcel/blobs/$layer"
''')
        missing = runtime.exec(run, check, check=False)
        assert missing.returncode != 0 and '[DQ:recovery_registry]' in missing.stdout
        runtime.exec(run, 'cd ~/quest\nsource platform.env\ndocker push "$REGISTRY/parcel:1"\n', timeout=120)
        assert runtime.exec(run, check, check=False).returncode == 0
        runtime.exec(run, '''set -euo pipefail
cd ~/quest
source platform.env
protected=$(jq -er .protected_image /run/dq/facts/0/recovery-baseline.json)
curl -fsS --cacert registry-ca.crt -u "$REGISTRY_USER:$REGISTRY_PASSWORD" -X DELETE "https://$REGISTRY/v2/protected/manifests/${protected##*@}"
''')
        protected = runtime.exec(run, check, check=False)
        assert protected.returncode != 0 and '[DQ:recovery_registry]' in protected.stdout
        evidence.update(cached_push='rejected', old_load_push='producer restored, consumer check rejected', solved='PASS', mutable_alias='rejected', schedule_resume='unit rejection verified', status_forgery='denied', archive_rewrite='rejected', missing_layer='rejected with running cached consumers', protected_deletion='rejected')
    except Exception as error:
        evidence['error'] = str(error)
        raise
    finally:
        try:
            runtime.teardown(run)
            evidence['teardown'] = 'PASS'
        finally:
            (folder / '097-no-shortcuts.json').write_text(json.dumps(evidence, indent=2) + '\n')
