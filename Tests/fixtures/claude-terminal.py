#!/usr/bin/env python3
"""Offline Claude transcript/PTY contract fixture. Never calls an agent or model."""
import json
import os
from pathlib import Path
import signal
import sys
import termios
import time
import tty
import uuid

config = Path(os.environ['CLAUDE_CONFIG_DIR'])
assert 'heka-remote-tests-' in str(config), 'Fixture must run in the isolated test configuration'
cwd = str(Path.cwd())
session = str(uuid.uuid4())
registry = config / 'sessions' / f'{os.getpid()}.json'
project = ''.join(c if c.isascii() and c.isalnum() else '-' for c in cwd)
log = config / 'projects' / project / f'{session}.jsonl'
registry.parent.mkdir(parents=True, exist_ok=True)
log.parent.mkdir(parents=True, exist_ok=True)
registry.write_text(json.dumps(dict(pid=os.getpid(), sessionId=session, cwd=cwd, startedAt=time.time() * 1000)))

def record(role, content):
    with log.open('a') as out:
        out.write(json.dumps(dict(type=role, uuid=str(uuid.uuid4()), sessionId=session, cwd=cwd,
                                 message=dict(role=role, content=content)), ensure_ascii=False) + '\n')

record('assistant', [{'type': 'text', 'text': 'CLAUDE_FIXTURE_READY\n\nUne **vraie conversation**, sans les rafraîchissements du terminal.'}])
old = termios.tcgetattr(0)
tty.setraw(0)
sys.stdout.write('\x1b[?1049h\x1b[?1h\x1b[?2004h\x1b[2J\x1b[HTUI_NOISE: agent menu / spinner\r\n> ')
sys.stdout.flush()
# Track exact bracketed-paste framing. CR/LF inside a paste are message content.
buffer = b''
message = b''
pasting = False
try:
    while True:
        part = os.read(0, 4096)
        if not part:
            break
        buffer += part
        while buffer:
            if buffer.startswith(b'\x1b[200~'):
                pasting = True
                buffer = buffer[6:]
            elif buffer.startswith(b'\x1b[201~'):
                pasting = False
                buffer = buffer[6:]
            elif buffer.startswith(b'\x1b') and len(buffer) < 6:
                break
            else:
                byte, buffer = buffer[:1], buffer[1:]
                if byte == b'\x03':
                    break
                if byte == b'\r' and not pasting:
                    text = message.decode('utf-8')
                    message = b''
                    record('user', text)
                    call = str(uuid.uuid4())
                    record('assistant', [{'type': 'tool_use', 'id': call, 'name': 'Read', 'input': {'file_path': 'hello.txt'}}])
                    record('user', [{'type': 'tool_result', 'tool_use_id': call, 'content': 'Bonjour du Mac', 'is_error': False}])
                    record('assistant', [{'type': 'text', 'text': 'STRUCTURED_REPLY\n\n```swift\nlet result = "✓"\n```'}])
                    # Deliberately no PTY output: only the transcript watcher can deliver this turn.
                else:
                    message += byte
finally:
    registry.unlink(missing_ok=True)
    termios.tcsetattr(0, termios.TCSANOW, old)
