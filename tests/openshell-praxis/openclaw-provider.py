#!/usr/bin/env python3
"""Synthetic OpenAI model exercising OpenClaw's real streamed write tool.

Only fixed test-file contents are requested. Recorded evidence never stores keys.
"""
import argparse
import json
from pathlib import Path
import sys
import threading

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'common'))
import provider

MARKER = 'OPENCLAW_TOOL_OK'
REQUIRE_THINKING_DISABLED = False
original_completion = provider.completion


def continuation(path, body):
    return any(item.get('role') == 'tool' and str(item.get('tool_call_id', '')).replace('_', '').startswith('callfixture')
               for item in body.get('messages', []))


def completion(path, body, missing_usage=False):
    if REQUIRE_THINKING_DISABLED and body.get('chat_template_kwargs', {}).get('enable_thinking') is not False:
        raise RuntimeError('Local OpenClaw request did not disable vLLM thinking')
    result = original_completion(path, body, missing_usage)
    message = result['choices'][0]['message']
    if continuation(path, body):
        message['content'] = MARKER
    else:
        names = [tool.get('function', {}).get('name') for tool in body.get('tools', [])]
        if 'exec' in names:
            raise RuntimeError('Unsupported exec tool was advertised')
        if 'write' not in names:
            raise RuntimeError('OpenClaw did not advertise its write tool')
        message['tool_calls'][0]['function'] = {
            'name': 'write',
            'arguments': json.dumps({'path': '/sandbox/openclaw-proof.txt', 'content': MARKER + '\n'})}
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18000)
    parser.add_argument('--credentialless', action='store_true')
    args = parser.parse_args()
    global REQUIRE_THINKING_DISABLED
    REQUIRE_THINKING_DISABLED = args.credentialless
    provider.continuation = continuation
    provider.completion = completion
    fixture = provider.Provider(host='127.0.0.1', control_host='127.0.0.1',
                                ports=(args.port, 0, 0), model='fixture-model',
                                local=args.credentialless)
    fixture.start()
    print('fixture ready', flush=True)
    threading.Event().wait()


if __name__ == '__main__':
    main()
