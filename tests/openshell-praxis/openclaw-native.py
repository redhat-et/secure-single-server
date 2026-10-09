#!/usr/bin/env python3
"""Pinned OpenClaw -> pinned Praxis -> synthetic model, with real write tools.

Requires a native x86_64 Linux container engine. This checks the client/gateway
contract; OpenShell policy enforcement is a separate RHEL runtime check.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.request
import uuid

import yaml

ROOT = Path(__file__).resolve().parents[2]
ENGINE = os.environ.get('CONTAINER_ENGINE', 'podman')
spec = importlib.util.spec_from_file_location('openclaw_fixture', Path(__file__).with_name('openclaw-provider.py'))
fixture_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture_module)
fixture_module.provider.continuation = fixture_module.continuation
fixture_module.provider.completion = fixture_module.completion
sys.path.insert(0, str(ROOT / 'tests/common'))
from evidence import save


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), text=True, capture_output=True, timeout=300, **kwargs)


def assert_authentication_rejection(result, proof, records):
    if result.returncode == 0 or proof.exists():
        raise RuntimeError('Authentication failure was reported as success')
    if not any(record.get('path') == '/v1/chat/completions'
               and record.get('method') == 'POST'
               and record.get('credential_ok') is False
               and record.get('classification_clean') is True for record in records):
        raise RuntimeError('No fresh upstream authentication rejection reached the model fixture')


def main():
    images = dict(line.split('=', 1) for line in (ROOT / 'openshell/configs/images.env').read_text().splitlines()
                  if line.startswith('ODH_'))
    claw_image = json.loads(images['ODH_OPENCLAW_IMAGE'])
    praxis_image = subprocess.check_output(['bash', '-c', 'source "$1/scripts/common/lib.sh"; printf %s "$DEFAULT_PRAXIS_IMAGE"',
                                           'test', str(ROOT)], text=True)
    for image in (claw_image, praxis_image):
        result = run(ENGINE, 'pull', image)
        if result.returncode:
            raise RuntimeError('Failed to pull pinned image: ' + result.stderr[-2000:])
    evidence = {'status': 'failed', 'openclaw_image': claw_image, 'praxis_image': praxis_image,
                'openshell_runtime': 'not covered by this client/gateway test', 'cases': []}
    try:
        for local, prefix in ((False, ""), (False, "/providers/team"), (True, "")):
            fixture_module.REQUIRE_THINKING_DISABLED = local
            fixture = fixture_module.provider.Provider(ports=(18000, 0, 0), model='fixture-model', local=local)
            fixture.start()
            name = 'openclaw-praxis-' + uuid.uuid4().hex[:10]
            try:
                with tempfile.TemporaryDirectory() as directory:
                    work = Path(directory)
                    work.chmod(0o777)
                    home = work / 'home'; home.mkdir(); home.chmod(0o777)
                    sandbox = work / 'sandbox'; sandbox.mkdir(); sandbox.chmod(0o777)
                    configdir = home / '.openclaw'; configdir.mkdir(); configdir.chmod(0o777)
                    template = ROOT / ('configs/vllm/openclaw' if local else 'configs/openshell-praxis/openclaw') / 'harness-provider.json.in'
                    config_path = configdir / 'openclaw.json'
                    rendered = run(sys.executable, ROOT / 'openshell/scripts/render-openclaw.py',
                                   template, config_path, '18080', 'fixture-model', prefix)
                    if rendered.returncode:
                        raise RuntimeError(rendered.stderr)
                    config = json.loads(config_path.read_text())
                    p = config['models']['providers']['praxis']
                    p['baseUrl'] = f'http://127.0.0.1:18080{prefix}/v1'
                    p['models'][0]['id'] = 'fixture-model'
                    config['agents']['defaults']['model']['primary'] = 'praxis/fixture-model'
                    (configdir / 'openclaw.json').write_text(json.dumps(config))
                    gateway = yaml.safe_load((ROOT / 'configs/vllm/praxis.yaml').read_text())
                    gateway['listeners'][0]['address'] = '127.0.0.1:18080'
                    filters = gateway['filter_chains'][0]['filters']
                    upstream = next(f for f in filters if f['filter'] == 'load_balancer')['clusters'][0]
                    upstream.update(endpoints=['127.0.0.1:18000'], http={'authority': 'localhost:18000'})
                    if not local:
                        filters.insert(-1, {'filter': 'credential_injection', 'clusters': [
                            {'name': 'openai', 'header': 'Authorization', 'header_prefix': 'Bearer ', 'env_var': 'OPENAI_API_KEY'}]})
                    if prefix:
                        filters.insert(-1, {'filter': 'path_rewrite', 'strip_prefix': prefix,
                                            'allow_rewrite_override': True,
                                            'conditions': [{'when': {'path_prefix': prefix + '/'}}]})
                    gateway_path = work / 'praxis.yaml'; gateway_path.write_text(yaml.safe_dump(gateway)); gateway_path.chmod(0o644)
                    started = run(ENGINE, 'run', '-d', '--name', name, '--network=host',
                                  '--read-only', '--cap-drop=all', '--security-opt=no-new-privileges',
                                  '--user=1001:1001', '-e', 'OPENAI_API_KEY=synthetic-openai',
                                  '-v', f'{gateway_path}:/etc/praxis/test.yaml:ro,Z', praxis_image,
                                  '-c', '/etc/praxis/test.yaml')
                    if started.returncode:
                        raise RuntimeError(started.stderr)
                    for attempt in range(30):
                        try:
                            urllib.request.urlopen('http://127.0.0.1:18080/v1/models', timeout=2).read()
                            break
                        except OSError:
                            if attempt == 29: raise
                            time.sleep(1)
                    args = [ENGINE, 'run', '--rm', '--network=host', '--user=1001:1001',
                            '--cap-drop=all', '--security-opt=no-new-privileges',
                            '-e', 'HOME=/home/sandbox',
                            '-v', f'{home}:/home/sandbox:Z', '-v', f'{sandbox}:/sandbox:Z',
                            '--entrypoint', '/usr/local/bin/openclaw', claw_image,
                            'agent', 'exec', '--config', '/home/sandbox/.openclaw/openclaw.json',
                            '--cwd', '/sandbox', '--timeout', '90', '--json',
                            'Write the proof file with the write tool, then confirm completion.']
                    if Path(ENGINE).name == 'podman':
                        args.insert(3, '--userns=keep-id:uid=1001,gid=1001')
                    response = run(*args)
                    if response.returncode:
                        raise RuntimeError('OpenClaw execution failed: ' + response.stderr[-3000:] + response.stdout[-3000:])
                    result = json.loads(response.stdout)
                    if not result.get('ok') or fixture_module.MARKER not in result.get('final', ''):
                        raise RuntimeError('Missing successful final answer: ' + response.stdout[-2000:])
                    if (sandbox / 'openclaw-proof.txt').read_text().strip() != fixture_module.MARKER:
                        raise RuntimeError('Tool file contents do not match')
                    records = list(fixture.records)
                    if not any(r.get('continuation') for r in records):
                        raise RuntimeError('No tool-result continuation reached model')
                    if not all(r['credential_ok'] for r in records):
                        raise RuntimeError('Upstream credential contract failed')
                    # Invalid upstream credentials must cause failure, never a successful empty run.
                    rejected_records = []
                    if not local:
                        fixture.openai_authorization = 'Bearer different-synthetic-key'
                        (sandbox / 'openclaw-proof.txt').unlink()
                        with fixture.lock:
                            record_count = len(fixture.records)
                        failed = run(*args)
                        with fixture.lock:
                            rejected_records = list(fixture.records[record_count:])
                        assert_authentication_rejection(failed, sandbox / 'openclaw-proof.txt', rejected_records)
                    evidence['cases'].append({'upstream': 'credentialless' if local else 'bearer-authenticated',
                                              'route_prefix': prefix, 'status': 'passed', 'records': records,
                                              'authentication_rejection_records': rejected_records})
                    print('PASS OpenClaw streaming, real write tool, continuation, and credentials:', evidence['cases'][-1]['upstream'])
            finally:
                fixture.close()
                run(ENGINE, 'rm', '-f', name)
        evidence['status'] = 'passed'
    finally:
        save('openclaw-native', evidence)


if __name__ == '__main__':
    main()
