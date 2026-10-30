#!/usr/bin/env python3
"""Offline Codex rollout/PTY contract fixture. Never calls an agent or model."""
import json
import os
from pathlib import Path
import sys
import termios
import tty
import uuid

root = Path(os.environ['AGENTUI_CODEX_FIXTURE_DIR'])
assert 'agentui-remote-tests-' in str(root), 'Fixture must run in the isolated test configuration'
session = str(uuid.uuid4())
rollout = root / f'rollout-2026-10-30T10-00-00-{session}.jsonl'
journal = rollout.open('a', encoding='utf-8')

def item(payload):
    journal.write(json.dumps(dict(type='response_item', payload=payload), ensure_ascii=False) + '\n')
    journal.flush()

item(dict(type='message', role='user', content=[dict(type='input_text', text='<environment_context>\n<cwd>fixture</cwd>\n</environment_context>')]))
item(dict(type='message', role='assistant', id=str(uuid.uuid4()), content=[dict(type='output_text', text='CODEX_FIXTURE_READY')]))
old = termios.tcgetattr(0)
tty.setraw(0)
sys.stdout.write('\x1b[?1049h\x1b[2J\x1b[HTUI_NOISE: codex composer\r\n> ')
sys.stdout.flush()
message = b''
try:
    while True:
        part = os.read(0, 4096)
        if not part:
            break
        for byte in part.replace(b'\x1b[200~', b'').replace(b'\x1b[201~', b''):
            if byte == 3:
                raise SystemExit
            if byte == 13:
                call = str(uuid.uuid4())
                item(dict(type='message', role='user', id=str(uuid.uuid4()), content=[dict(type='input_text', text=message.decode('utf-8'))]))
                item(dict(type='custom_tool_call', call_id=call, name='exec', input='cat hello.txt'))
                item(dict(type='custom_tool_call_output', call_id=call,
                          output=[dict(type='input_text', text='Script completed\nWall time 0.0 seconds\nOutput:\nBonjour du Mac')]))
                item(dict(type='message', role='assistant', id=str(uuid.uuid4()), content=[dict(type='output_text', text='CODEX_STRUCTURED_REPLY')]))
                message = b''
            else:
                message += bytes([byte])
finally:
    journal.close()
    termios.tcsetattr(0, termios.TCSANOW, old)
