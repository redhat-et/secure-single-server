#!/usr/bin/env python3
"""Controlled model driving OpenCode's real write and bash tools, without keys."""
import argparse
import json
from pathlib import Path
import sys
import threading
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'common'))
import provider

MARKER = 'OPENCODE_TOOL_OK'
original_completion = provider.completion


def continuation(path, body):
    return any(item.get('role') == 'tool' and item.get('tool_call_id') == 'call_bash'
               for item in body.get('messages', []))


def completion(path, body, missing_usage=False):
    result = original_completion(path, body, missing_usage)
    choice = result['choices'][0]
    message = choice['message']
    names = {tool.get('function', {}).get('name') for tool in body.get('tools', [])}
    if not names or continuation(path, body):
        message.pop('tool_calls', None)
        message['content'] = MARKER
        choice['finish_reason'] = 'stop'
        return result
    if not {'write', 'bash'} <= names:
        raise RuntimeError('OpenCode did not advertise write and bash tools')
    written = any(item.get('role') == 'tool' and item.get('tool_call_id') == 'call_write'
                  for item in body.get('messages', []))
    function = {'name': 'bash', 'arguments': json.dumps({
        'command': 'node /sandbox/opencode-proof.cjs',
        'description': 'Run the fixed proof script', 'timeout': 10000})} if written else {
        'name': 'write', 'arguments': json.dumps({
            'filePath': '/sandbox/opencode-proof.cjs',
            'content': "require('node:fs').writeFileSync('/sandbox/opencode-exec-proof.txt', 'OPENCODE_TOOL_OK\\n');\n"})}
    message['content'] = None
    message['tool_calls'] = [{'id': 'call_bash' if written else 'call_write',
                             'type': 'function', 'function': function}]
    choice['finish_reason'] = 'tool_calls'
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18000)
    args = parser.parse_args()
    provider.continuation = continuation
    provider.completion = completion
    fixture = provider.Provider(host='127.0.0.1', control_host='127.0.0.1',
                                ports=(args.port, 0, 0), model='fixture-model', local=True)
    fixture.start()
    print('fixture ready', flush=True)
    threading.Event().wait()


if __name__ == '__main__':
    main()
