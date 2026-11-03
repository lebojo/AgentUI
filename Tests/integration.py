#!/usr/bin/env python3
"""Run against a Debug .app. Uses isolated repositories and state, never user data."""
import json
import os
import shutil
import shlex
import pathlib
import subprocess
import sys
import tempfile
import time
import uuid

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/heka-build/Build/Products/Debug/Heka.app/Contents/MacOS/Heka')
screenshots = pathlib.Path(__file__).resolve().parents[1] / '.impeccable/review'
screenshots.mkdir(parents=True, exist_ok=True)
for name in [name for name in os.environ if name.startswith('HEKA_')]:
    del os.environ[name]
root = pathlib.Path(tempfile.mkdtemp(prefix='heka-integration-')).resolve()
state = root / 'state'
repo = root / 'Studio' / 'App macOS'
repo.mkdir(parents=True)
app = None
instance = None

def wait_for(predicate, description, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError('Timed out: ' + description)

def start():
    global app, instance
    instances = state / 'Instances'
    shutil.rmtree(instances, ignore_errors=True)
    app = subprocess.Popen([str(binary), '-AppleLanguages', '(en)'], env=os.environ | {'HEKA_STATE_DIRECTORY': str(state)},
                           stdout=open(root / 'app.log', 'a'), stderr=subprocess.STDOUT)
    registered = lambda: [entry for entry in instances.iterdir() if entry.name.isdigit()] if instances.is_dir() else []
    wait_for(registered, 'app bridge')
    instance = pathlib.Path(registered()[0].read_text())

def request(action, **kwargs):
    ident = str(uuid.uuid4()).upper()
    payload = {'id': ident, 'action': action, 'command': [], **kwargs}
    pending = instance / (ident + '.pending')
    pending.write_text(json.dumps(payload))
    pending.rename(instance / (ident + '.request'))
    response = instance / (ident + '.response')
    wait_for(response.exists, action)
    result = json.loads(response.read_text())
    response.unlink()
    assert result['ok'], result
    return result

def activate():
    wait_for(lambda: request('debug.activate').get('message') == 'key', 'native key window', timeout=10)

def stop():
    if app and app.poll() is None:
        request('debug.stop')
        app.wait(timeout=10)

def cli(*args, ok=True, extra_env=None):
    env = os.environ | {'HEKA_INSTANCE': str(instance)} | (extra_env or {})
    result = subprocess.run([str(instance/'bin/heka'), *args], env=env, capture_output=True, text=True, timeout=30)
    data = json.loads(result.stdout)
    assert data['ok'] == ok and (result.returncode == 0) == ok, (args, data, result.stderr)
    return data

def git(*args):
    return subprocess.run(['/usr/bin/git','-C',str(repo),*args],check=True,capture_output=True,text=True).stdout.strip()

try:
    git('init', '-b', 'main')
    git('-c','user.name=Heka Tests','-c','user.email=tests@example.invalid','commit','--allow-empty','-m','Fixture')
    start()
    # The normal Add action recognizes a parent folder of repositories.
    plain = repo.parent / 'Documents'
    plain.mkdir()
    nested = repo.parent / 'Clients' / 'Backend'
    nested.mkdir(parents=True)
    subprocess.run(['/usr/bin/git','-C',str(nested),'init','-b','develop'],check=True,capture_output=True)
    request('debug.addLocation',path=str(repo.parent))
    imported = cli('list')['workspace']
    folders = {f['name']: f for f in imported['folders']}
    assert set(folders) == {'Studio','Clients'} and folders['Clients']['parentID'] == folders['Studio']['id']
    assert {p['path']: p['folderID'] for p in imported['projects']} == {str(repo): folders['Studio']['id'], str(nested): folders['Clients']['id']}
    request('debug.import',path=str(repo.parent))
    assert cli('list')['workspace'] == imported, 'Reimport must preserve folders, IDs and sessions'
    print('PASS automatic container import, folder hierarchy and idempotent reimport', flush=True)

    project = cli('project','add',str(repo))
    pid, wid = project['projectID'], project['worktreeID']
    # A symlink to an already imported repository must not create another project.
    alias = root / 'Alias'
    alias.symlink_to(repo)
    same = cli('project','add',str(alias))
    assert same['projectID'] == pid
    print('PASS project import and canonical-path deduplication', flush=True)

    selected_terminal = cli('list')['workspace']['selection']
    wait_for(lambda: request('debug.git',name=selected_terminal).get('message') == 'main', 'initial green branch badge')
    git('switch','-c','feature/green-chip')
    wait_for(lambda: request('debug.git',name=selected_terminal).get('message') == 'feature/green-chip', 'live branch update')
    request('debug.send',name=selected_terminal,command=['cd ' + shlex.quote(str(nested))])
    wait_for(lambda: request('debug.git',name=selected_terminal).get('message') == 'develop', 'branch follows terminal cd')
    request('debug.send',name=selected_terminal,command=['cd ' + shlex.quote(str(plain))])
    wait_for(lambda: request('debug.git',name=selected_terminal).get('path') == str(plain)
             and request('debug.git',name=selected_terminal).get('message') is None, 'badge disappears outside Git')
    request('debug.send',name=selected_terminal,command=['cd ' + shlex.quote(str(repo))])
    git('switch','main')
    wait_for(lambda: request('debug.git',name=selected_terminal).get('message') == 'main', 'badge returns on entering repository')
    print('PASS automatic branch monitoring, shell cd and non-Git badge removal', flush=True)

    marker = root / 'terminal-result.json' 
    literal = "quotes ' spaces $(literal) `literal`"
    child = ['/usr/bin/python3','-c',
             'import os,json,sys;json.dump({"cwd":os.getcwd(),"arg":sys.argv[2],"project":os.environ.get("HEKA_PROJECT_ID"),"worktree":os.environ.get("HEKA_WORKTREE_ID"),"tty":os.isatty(0)},open(sys.argv[1],"w"))',str(marker),literal]
    terminal = cli('terminal','create','--project',pid,'--worktree',wid,'--name','Contrôle des arguments','--',*child)
    wait_for(marker.exists, 'child process')
    data = json.loads(marker.read_text())
    assert data == {'cwd':str(repo), 'arg':literal, 'project':pid, 'worktree':wid, 'tty':True}, data
    print('PASS real PTY, cwd, inherited context and literal command arguments', flush=True)

    # Parent agent launches a child through the CLI from its own PTY context.
    nested = root / 'nested.json'
    parent = cli('terminal','create','--project',pid,'--worktree',wid,'--name','Délégation', '--',
                 '/bin/zsh','-c','"$HEKA_CLI" terminal create --name "Agent enfant" > "$1"', 'heka-test', str(nested))
    wait_for(lambda: nested.exists() and nested.stat().st_size > 0, 'nested agent request')
    spawned = json.loads(nested.read_text())
    assert spawned['ok'] and spawned['worktreeID'] == wid
    print('PASS agent-created sibling from inside a live terminal', flush=True)

    echo = cli('terminal','create','--project',pid,'--worktree',wid,'--name','Écho','--','/usr/bin/python3','-c',
               'import sys\nwhile True:\n    line = input("> ")\n    if line == "quit": sys.exit(3)\n    print("got: " + line, flush=True)')
    echo_id = echo['terminalID']
    wait_for(lambda: '>' in cli('terminal','read','--terminal',echo_id)['output'], 'child prompt')
    sent = cli('terminal','send','--terminal',echo_id,'--enter','--','hello',"$(literal) world")
    assert sent['running'] and sent['terminalID'] == echo_id and sent['worktreeID'] == wid, sent
    cli('terminal','wait','--terminal',echo_id,'--idle','0.5','--timeout','10')
    assert 'got: hello $(literal) world' in cli('terminal','read','--terminal',echo_id)['output']
    piped = subprocess.run([str(instance/'bin/heka'),'terminal','send','--terminal',echo_id,'--enter','--stdin'], input='from stdin\n',
                           env=os.environ | {'HEKA_INSTANCE': str(instance)}, capture_output=True, text=True, timeout=30)
    assert json.loads(piped.stdout)['ok'], piped
    wait_for(lambda: cli('terminal','read','--terminal',echo_id,'--lines','1')['output'] == '> ', 'stdin message answered')
    assert 'got: from stdin' in cli('terminal','read','--terminal',echo_id,'--lines','3')['output']
    cli('terminal','send','--terminal',echo_id,'--','abcX')
    cli('terminal','send','--terminal',echo_id,'--key','backspace','--key','enter')
    wait_for(lambda: 'got: abc\n' in cli('terminal','read','--terminal',echo_id)['output'], 'keys pressed in order')
    assert 'conversation' in cli('terminal','read','--terminal',echo_id,'--reply',ok=False)['message']
    still = cli('terminal','wait','--terminal',echo_id,'--exit','--timeout','1',ok=False)
    assert still['running'] and 'still running' in still['message'], still
    cli('terminal','send','--terminal',echo_id,'--',ok=False)
    cli('terminal','send','--terminal',echo_id,'--','x',ok=False,extra_env={'HEKA_TERMINAL_ID': echo_id})
    cli('terminal','send','--terminal',echo_id,'--','quit')
    cli('terminal','send','--terminal',echo_id,'--enter')
    exited = cli('terminal','wait','--terminal',echo_id,'--exit','--timeout','10')
    assert not exited['running'] and exited['exitCode'] == 3, exited
    assert 'ended' in cli('terminal','send','--terminal',echo_id,'--enter','--','again',ok=False)['message']
    assert 'not found' in cli('terminal','read','--terminal',str(uuid.uuid4()),ok=False)['message']
    closable = cli('terminal','create','--project',pid,'--worktree',wid,'--name','À fermer')
    closed = cli('terminal','close','--terminal',closable['terminalID'])
    assert closed['removed'] and not closed['running'], closed
    assert closable['terminalID'] not in [t['id'] for p in cli('list')['workspace']['projects'] for w in p['worktrees'] for t in w['terminals']]
    cli('terminal','close','--terminal',closable['terminalID'],ok=False)
    print('PASS an agent sends input to another terminal, presses keys, reads its output, waits for it and closes it', flush=True)

    def from_terminal(script, output, branch=None):
        create = ('worktree','create','--project',pid,'--branch',branch) if branch else ('terminal','create','--project',pid,'--worktree',wid)
        created = cli(*create,'--','/bin/zsh','-c',script + ' > "$1"; sleep 30','heka-test',str(output))
        wait_for(lambda: output.exists() and output.stat().st_size > 0, 'reply in the closing terminal')
        return created, json.loads(output.read_text())
    terminals = lambda: [t['id'] for p in cli('list')['workspace']['projects'] for w in p['worktrees'] for t in w['terminals']]
    worktrees = lambda: [w['id'] for p in cli('list')['workspace']['projects'] for w in p['worktrees']]
    itself, reply = from_terminal('"$HEKA_CLI" terminal close --terminal "$HEKA_TERMINAL_ID"', root / 'close-self.json')
    assert reply['ok'] and reply['closesCaller'] and reply['removed'], reply
    wait_for(lambda: itself['terminalID'] not in terminals(), 'terminal closed after its reply')
    dirty, refusal = from_terminal('touch draft.txt; "$HEKA_CLI" worktree delete --worktree "$HEKA_WORKTREE_ID"', root / 'dirty-self.json',
                                   branch='feature/self-dirty')
    assert not refusal['ok'] and 'force' in refusal['message'] and dirty['worktreeID'] in worktrees(), refusal
    assert dirty['terminalID'] in terminals() and pathlib.Path(dirty['path']).is_dir()
    merged, reply = from_terminal('"$HEKA_CLI" worktree delete --worktree "$HEKA_WORKTREE_ID" --delete-branch', root / 'delete-self.json',
                                  branch='feature/self-merged')
    assert reply['ok'] and reply['closesCaller'] and reply['worktreeID'] == merged['worktreeID'], reply
    wait_for(lambda: merged['worktreeID'] not in worktrees() and not pathlib.Path(merged['path']).exists(), 'own worktree deleted after the reply')
    wait_for(lambda: not git('branch','--list','feature/self-merged'), 'merged branch deleted with its own worktree')
    cli('worktree','delete','--worktree',dirty['worktreeID'],'--force')
    print('PASS an agent closes its own terminal and deletes its own worktree, after the reply and only once everything is checked', flush=True)

    worktree = cli('worktree','create','--project',pid,'--branch','feature/native-sidebar','--name','Interface')
    assert pathlib.Path(worktree['path']).is_dir() and git('branch','--show-current') == 'main'
    cli('worktree','create','--project',pid,'--branch','feature/native-sidebar',ok=False)
    print('PASS worktree creation, isolated branch and actionable duplicate-branch error', flush=True)

    # Force Git to remain in post-checkout after registering its new worktree.
    # A simultaneous UI refresh must not append that worktree a second time.
    hook = repo / '.git/hooks/post-checkout'
    hook.write_text('#!/bin/sh\nsleep 1\n')
    hook.chmod(0o755)
    pending = subprocess.Popen([str(instance/'bin/heka'),'worktree','create','--project',pid,'--branch','feature/concurrent-refresh'],
                               env=os.environ | {'HEKA_INSTANCE':str(instance)}, stdout=subprocess.PIPE, text=True)
    wait_for(lambda: 'feature/concurrent-refresh' in git('worktree','list'), 'worktree registered before hook finishes')
    request('debug.refresh',projectID=pid)
    result = json.loads(pending.communicate(timeout=15)[0])
    assert result['ok']
    hook.unlink()
    print('PASS concurrent refresh/create does not duplicate a worktree', flush=True)

    outside_env = os.environ | {'HEKA_STATE_DIRECTORY': str(state)}
    subfolder = repo / 'Sources'
    subfolder.mkdir(exist_ok=True)
    outside = subprocess.run([str(instance/'bin/heka'),'terminal','create','--name','Outside'], cwd=subfolder,
                             env=outside_env, capture_output=True, text=True, timeout=30)
    data = json.loads(outside.stdout)
    assert data['ok'] and data['projectID'] == pid and data['worktreeID'] == wid, data
    elsewhere = subprocess.run([str(instance/'bin/heka'),'terminal','create'], cwd=root,
                               env=outside_env, capture_output=True, text=True, timeout=30)
    assert elsewhere.returncode != 0 and '--project' in json.loads(elsewhere.stdout)['message']
    print('PASS outside Heka, the CLI finds the running app and the project of the current directory', flush=True)
    linked = root / 'linked-bin' / 'heka'
    linked.parent.mkdir(exist_ok=True)
    linked.symlink_to(binary)
    through_link = subprocess.run([str(linked),'list'], cwd=subfolder, env=outside_env, capture_output=True, text=True, timeout=30)
    assert through_link.returncode == 0 and json.loads(through_link.stdout)['ok'], through_link
    print('PASS the heka link installed in PATH runs the CLI, not a second app', flush=True)

    disposable = cli('worktree','create','--project',pid,'--branch','feature/disposable')
    (pathlib.Path(disposable['path']) / 'draft.txt').write_text('work in progress')
    refused = cli('worktree','delete','--worktree',disposable['worktreeID'],ok=False)
    assert 'force' in refused['message'] and pathlib.Path(disposable['path']).is_dir()
    main_worktree = next(w for p in cli('list')['workspace']['projects'] if p['id'] == pid for w in p['worktrees'] if w['isPrimary'])
    cli('worktree','delete','--worktree',main_worktree['id'],ok=False)
    deleted = cli('worktree','delete','--worktree',disposable['worktreeID'],'--force')
    remaining = [w['id'] for p in cli('list')['workspace']['projects'] for w in p['worktrees']]
    assert deleted['path'] == disposable['path'] and not pathlib.Path(disposable['path']).exists()
    assert disposable['worktreeID'] not in remaining and git('branch','--list','feature/disposable')
    print('PASS agent worktree deletion keeps uncommitted work unless forced, never the main folder, and keeps the branch', flush=True)

    request('debug.folder',name='Dossier virtuel',projectID=pid)
    snapshot = cli('list')['workspace']
    p = next(x for x in snapshot['projects'] if x['id'] == pid)
    assert len(p['worktrees']) == 3, p
    assert p['folderID'] == snapshot['folders'][-1]['id']
    selected = snapshot['selection']
    # Switch away and back, with the same live session IDs retained.
    request('debug.select',name=worktree['terminalID'])
    request('debug.select',name=selected)
    assert cli('list')['workspace']['selection'] == selected
    print('PASS nested grouping, no duplicate primary worktree, terminal selection', flush=True)

    # Optional diagnostic captures; cacheDisplay does not validate native vibrancy/colors.
    for name, width, appearance in ([('desktop',1180,'dark'),('compact',780,'dark'),('light',1180,'light')] if os.environ.get('HEKA_CAPTURE_TOOL') else []):
        # First layout, then capture after SwiftUI has rendered the changed size/appearance.
        target = str(screenshots / (name+'.png'))
        request('debug.capture',path=target,name=appearance,command=[str(width)])
        time.sleep(.4)
        capture = request('debug.capture',path=target,name=appearance,command=[str(width)])
        if os.environ.get('HEKA_CAPTURE_TOOL'):
            subprocess.run([os.environ['HEKA_CAPTURE_TOOL'],target],check=True)
    if os.environ.get('HEKA_CAPTURE_TOOL'):
        print('Captured diagnostic images; inspect before treating them as visual evidence.', flush=True)

    if not os.environ.get('HEKA_SKIP_WINDOW_TESTS'):
        # Exercise both the actual Command-W event route and the native Close menu.
        sleeper = next(p for p in cli('list')['workspace']['projects'] if p['id'] != pid)
        sleeper_id = sleeper['worktrees'][0]['terminals'][0]['id']
        request('debug.select', name=sleeper_id)
        activate()
        time.sleep(.3)
        result = request('debug.closeShortcut')
        assert result['message'] == 'visible', result
        slept = cli('list')['workspace']
        dormant = next(p for p in slept['projects'] if p['id'] == sleeper['id'])
        assert all(not w['terminals'] for w in dormant['worktrees']), dormant
        assert slept.get('selection') is None, 'Do not jump to another project when last terminal closes'
        request('debug.wake', projectID=sleeper['id'])
        awake = cli('list')['workspace']
        fresh = awake['selection']
        assert fresh != sleeper_id and fresh is not None
        extra = cli('terminal','create','--project',sleeper['id'],'--worktree',sleeper['worktrees'][0]['id'])
        activate()
        time.sleep(.2)
        assert request('debug.closeShortcut',name='menu')['message'] == 'visible'
        assert cli('list')['workspace']['selection'] == extra['terminalID'], 'Select remaining terminal in same project'
        request('debug.closeShortcut',name='menu')
        assert cli('list')['workspace'].get('selection') is None
        print('PASS native Command-W, Close menu, dormant last project and click-to-reopen action', flush=True)

    else:
        print('SKIP native window/keyboard checks: explicitly running without WindowServer focus', flush=True)

    # A failed durable write must not be acknowledged as success by the agent CLI.
    if os.geteuid() != 0:
        state.chmod(0o500)
        try:
            failed_save = cli('terminal','create','--project',pid,'--worktree',wid,'--name','Pending persistence',ok=False)
            assert failed_save.get('terminalID') and 'saving' in failed_save['message']
            assert failed_save['terminalID'] not in json.dumps(json.loads((state/'workspace.json').read_text()))
        finally:
            state.chmod(0o700)
        request('debug.flush')
        saved_state = json.loads((state/'workspace.json').read_text())
        saved_ids = [t['id'] for p in saved_state['projects'] for w in p['worktrees'] for t in w['terminals']]
        assert saved_ids.count(failed_save['terminalID']) == 1
        print('PASS CLI rejects unsaved success; retry persists without recreating terminal', flush=True)

    cancellation_marker = root / 'blocked-hook.pid'
    hook.write_text('#!/bin/sh\necho $$ > ' + shlex.quote(str(cancellation_marker)) + '\nexec /bin/sleep 30\n')
    hook.chmod(0o755)
    try:
        cancelled = request('debug.cancelWorktree', projectID=pid, branch='feature/cancelled-recovery', path=str(cancellation_marker))
    finally:
        hook.unlink()
    recovered_project = next(p for p in cancelled['workspace']['projects'] if p['id'] == pid)
    partial = [w for w in recovered_project['worktrees'] if w['path'] == cancelled['path']]
    assert len(partial) == 1 and partial[0]['terminals'] == [] and pathlib.Path(partial[0]['path']).is_dir()
    assert 'partial' in cancelled['message']
    print('PASS cancelled creation reconciles partial worktree without spawning terminal or deleting files', flush=True)

    before = cli('list')['workspace']
    marker.unlink()
    stop()
    start()
    after = cli('list')['workspace']
    assert before == after, (before,after)
    request('debug.select', name=terminal['terminalID'])
    time.sleep(.5)
    assert not marker.exists(), 'Restart must not replay the old agent command'
    print('PASS persisted organization and no automatic command replay after relaunch', flush=True)
    if not os.environ.get('HEKA_SKIP_WINDOW_TESTS'):
        request('debug.select')
        activate()
        time.sleep(.2)
        assert request('debug.closeShortcut',name='menu')['message'] == 'closed'
        print('PASS Command-W closes window when no terminal is selected', flush=True)
    stop()
    state_file = state / 'workspace.json'
    state_file.write_text('invalid json')
    start()
    failed = cli('project','add',str(repo),ok=False)
    assert 'unreadable' in failed['message']
    assert state_file.read_text() == 'invalid json'
    stop()
    print('PASS corrupt state preserves original and rejects unsavable mutations', flush=True)
    print('All integration tests passed.', flush=True)
finally:
    if app and app.poll() is None:
        try: stop()
        except Exception: app.terminate(); app.wait(timeout=10)
    # Only disposable test data is removed, including its temporary Git worktrees.
    import shutil
    shutil.rmtree(root)
