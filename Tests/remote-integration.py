#!/usr/bin/env python3
"""Real Mac host / TCP / PTY tests in an isolated, loopback-only Debug workspace."""
import base64
import functools
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import time
import uuid

binary = Path(sys.argv[1])
root = Path(tempfile.mkdtemp(prefix="agentui-remote-tests-"))
state = root / "state"
repo = root / "Mobile fixture"
repo.mkdir()
(repo / "hello.txt").write_text("Bonjour du Mac\n")
subprocess.run(["/usr/bin/git", "-C", str(repo), "init", "-b", "main"], check=True, capture_output=True)
subprocess.run(["/usr/bin/git", "-C", str(repo), "add", "."], check=True, capture_output=True)
subprocess.run(["/usr/bin/git", "-C", str(repo), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "commit", "-m", "Fixture"], check=True, capture_output=True)
app = None
instance = None
PAIRING_CODE = "ABCD-EFGH-JKLM"
NOTIFICATIONS = ("repositoryChanged", "conversationsChanged", "installedAgents")
# Never connect integration clients to the user's running host on the default port.
with socket.socket() as reservation:
    reservation.bind(("127.0.0.1", 0))
    port = reservation.getsockname()[1]
print("Test port:", port, flush=True)


def wait_for(predicate, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.05)
    raise AssertionError("Timed out")


def bridge(action, **kwargs):
    ident = str(uuid.uuid4()).upper()
    pending = instance / (ident + ".pending")
    payload = dict(id=ident, action=action, command=[])
    payload.update(kwargs)
    pending.write_text(json.dumps(payload))
    pending.rename(instance / (ident + ".request"))
    response = instance / (ident + ".response")
    wait_for(response.exists)
    result = json.loads(response.read_text())
    response.unlink()
    assert result["ok"], result
    return result


@functools.cache
def pairing_key(code):
    return hashlib.pbkdf2_hmac("sha256", code.replace("-", "").encode(), b"AgentUI pairing", 100_000)


def connect(code=PAIRING_CODE, timeout=15):
    key = pairing_key(code)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.maximum_version = ssl.TLSVersion.TLSv1_2
    context.set_ciphers("ECDHE-PSK-CHACHA20-POLY1305")
    context.set_psk_client_callback(lambda hint: ("AgentUI", key))
    return context.wrap_socket(socket.create_connection(("127.0.0.1", port), timeout=timeout))


def send(sock, value):
    data = json.dumps(value).encode()
    sock.sendall(struct.pack("!I", len(data)) + data)


def read(sock, notifications=False):
    while True:
        event = read_frame(sock)
        if notifications or not any(name in event for name in NOTIFICATIONS):
            return event


def read_frame(sock):
    def exact(count):
        data = b""
        while len(data) < count:
            chunk = sock.recv(count - len(data))
            if not chunk:
                raise EOFError("Host closed connection")
            data += chunk
        return data
    count = struct.unpack("!I", exact(4))[0]
    assert count <= 4 * 1024 * 1024
    return json.loads(exact(count))


def rpc(action, **kwargs):
    with connect() as sock:
        send(sock, {action: kwargs})
        reply = read(sock)
        if "error" in reply:
            raise ValueError(reply["error"])
        return json.loads(base64.b64decode(reply["payload"]))


PROTOCOL = 6


def watch(terminal=None, chat=True):
    sock = connect()
    request = dict(version=PROTOCOL, prefersChat=chat)
    if terminal:
        request["terminal"] = terminal
    send(sock, {"watch": request})
    assert "workspace" in read(sock)
    return sock


try:
    print("Fixture:", root, flush=True)
    log = open(root / "app.log", "w")
    app = subprocess.Popen([str(binary), "-localHost.enabled", "YES", "-localHost.pairingCode", PAIRING_CODE, "-sessionDisplayMode", "chat"],
                           env=os.environ | {"AGENTUI_STATE_DIRECTORY": str(state), "AGENTUI_TEST_HOST_PORT": str(port), "CLAUDE_CONFIG_DIR": str(root / "claude")}, stdout=log, stderr=subprocess.STDOUT)
    wait_for(lambda: (state / "instance-path").exists())
    instance = Path((state / "instance-path").read_text())
    bridge("debug.addLocation", path=str(repo))
    def host_ready():
        try:
            rpc("workspace", version=PROTOCOL)
            return True
        except (ConnectionError, OSError, ssl.SSLError):
            return False
    wait_for(host_ready)
    workspace = rpc("workspace", version=PROTOCOL)
    terminal = workspace["selection"]
    project = workspace["projects"][0]
    worktree = project["worktrees"][0]
    assert len(workspace["projects"]) == 1
    assert Path(worktree["path"]).resolve() == repo.resolve(), "Refusing to run against a non-fixture host"
    try:
        rpc("workspace", version=999)
        raise AssertionError("Incompatible version accepted")
    except ValueError:
        pass
    with connect() as sock:
        send(sock, {"watch": dict(version=PROTOCOL + 1)})
        reply = read(sock)
        assert "Versions incompatibles" in reply["failure"]["_0"] and "Versions incompatibles" in reply["error"], reply
    try:
        rpc("futureRequest", terminal=terminal)
        raise AssertionError("An unknown request was accepted")
    except ValueError as error:
        assert "Versions incompatibles" in str(error), error
    print("PASS real host connection and protocol version", flush=True)

    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        send(sock, {"workspace": dict(version=PROTOCOL)})
        try:
            assert b"projects" not in sock.recv(65536)
        except ConnectionError:
            pass
    try:
        with connect("MNPQ-RSTU-VWXY") as sock:
            send(sock, {"workspace": dict(version=PROTOCOL)})
            read(sock)
        raise AssertionError("Wrong pairing code accepted")
    except (ssl.SSLError, ConnectionError, EOFError):
        pass
    with connect() as sock:
        assert sock.cipher()[0] == "ECDHE-PSK-CHACHA20-POLY1305", sock.cipher()
    print("PASS unencrypted and wrong-code clients refused, forward-secret cipher", flush=True)

    idle = [socket.create_connection(("127.0.0.1", port), timeout=5) for _ in range(8)]
    time.sleep(1)
    try:
        rpc("workspace", version=PROTOCOL)
        raise AssertionError("A peer exceeded its connection limit")
    except (ssl.SSLError, ConnectionError, EOFError, OSError):
        pass
    for sock in idle:
        sock.close()
    wait_for(host_ready)
    print("PASS one peer cannot hold every connection slot", flush=True)

    with watch() as sock:
        sock.settimeout(.5)
        try:
            read(sock)
            raise AssertionError("Unexpected idle traffic")
        except socket.timeout:
            pass
    print("PASS no workspace polling / idle traffic", flush=True)

    with watch(terminal) as sock:
        first = read(sock)["terminal"]["_0"]
        assert not first["isChat"] and not first["transcript"], "A shell without an agent stays a terminal in chat mode"
        request_id = str(uuid.uuid4()).upper()
        command = "printf '\\101\\107\\105\\116\\124\\125\\111_REMOTE_OK\\n'\r"
        send(sock, {"streamInput": dict(request=request_id, terminal=terminal,
                                       data=base64.b64encode(command.encode()).decode(), message=None)})
        ack = False
        found = False
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and not (ack and found):
            event = read(sock)
            if "inputResult" in event:
                ack = event["inputResult"]["request"] == request_id
                assert "error" not in event["inputResult"]
            if "terminal" in event:
                snapshot = event["terminal"]["_0"]
                assert not snapshot["isChat"]
                found = found or b"AGENTUI_REMOTE_OK" in base64.b64decode(snapshot["output"])
        assert ack and found
    try:
        rpc("input", id=terminal, data=base64.b64encode(b"echo CHAT_TEXT_IN_SHELL\r").decode(), message="echo CHAT_TEXT_IN_SHELL")
        raise AssertionError("A chat message was typed into the shell")
    except ValueError as error:
        assert "L’agent s’est arrêté" in str(error), error
    print("PASS a shell stays a terminal in chat mode, duplex input acknowledgement, real PTY output and no chat text run by the shell", flush=True)

    with watch(terminal, chat=False) as sock:
        snapshot = read(sock)["terminal"]["_0"]
        assert b"AGENTUI_REMOTE_OK" in base64.b64decode(snapshot["output"])
        assert not snapshot["transcript"]
    print("PASS reconnect / terminal replay / no duplicate chat payload", flush=True)

    with watch(terminal, chat=False) as sock:
        original = read(sock)["terminal"]["_0"]["identity"]
        bridge("debug.reopen", name=terminal)
        while True:
            event = read(sock)
            if "terminal" in event and event["terminal"]["_0"]["identity"] != original:
                assert b"\x1b[3J\x1b[2J" in base64.b64decode(event["terminal"]["_0"]["output"])
                break
        command = "printf '\\116\\105\\127_SESSION_OUTPUT\\n'\r"
        rpc("input", id=terminal, data=base64.b64encode(command.encode()).decode())
        while True:
            event = read(sock)
            if "terminal" in event and b"NEW_SESSION_OUTPUT" in base64.b64decode(event["terminal"]["_0"]["output"]):
                break
    print("PASS same-ID session replacement rebinds stream", flush=True)

    echo = bridge("terminal.create", projectID=project["id"], worktreeID=worktree["id"], name="Echo",
                  command=["/bin/cat"])["terminalID"]
    with watch(echo, chat=False):
        try:
            rpc("launchAgent", terminal=echo, agent="codex")
            raise AssertionError("An agent must not be typed into a running program")
        except ValueError as error:
            assert "invite du shell" in str(error), error
    stub = "codex() { printf '\\101\\107\\105\\116\\124_STUB_STARTED\\n'; }\r"
    rpc("input", id=terminal, data=base64.b64encode(stub.encode()).decode())
    with watch(terminal, chat=False) as sock:
        assert rpc("launchAgent", terminal=terminal, agent="codex") is True
        deadline = time.monotonic() + 10
        while b"AGENT_STUB_STARTED" not in base64.b64decode(read(sock).get("terminal", {}).get("_0", {}).get("output", "")):
            assert time.monotonic() < deadline, "The agent shortcut did not run its command at the shell prompt"
    print("PASS agent shortcut refuses a running program and launches at the shell prompt", flush=True)

    assert rpc("text", terminal=terminal, path=str(repo / "hello.txt")) == "Bonjour du Mac\n"
    listing = rpc("children", terminal=terminal, path=str(repo))
    assert listing["omitted"] == 0, listing
    children = listing["entries"]
    assert any(entry["url"].endswith("hello.txt") for entry in children)
    for forbidden in ["/etc/passwd", str(repo / "../../etc/passwd")]:
        try:
            rpc("text", terminal=terminal, path=forbidden)
            raise AssertionError("Read outside worktree allowed")
        except ValueError:
            pass
    (repo / "escape").symlink_to("/etc/passwd")
    try:
        rpc("text", terminal=terminal, path=str(repo / "escape"))
        raise AssertionError("Symlink escape allowed")
    except ValueError:
        pass
    print("PASS remote file reading and path / symlink confinement", flush=True)

    (repo / "hello.txt").write_text("Changed from the Mac\n")
    local = rpc("git", terminal=terminal)
    change = next(change for change in local["changes"] if change["path"] == "hello.txt")
    diff = rpc("diff", terminal=terminal, change=change)
    assert "Changed from the Mac" in diff["sections"][0]["patch"]
    terminals = lambda: rpc("workspace", version=PROTOCOL)["projects"][0]["worktrees"][0]["terminals"]
    before = len(terminals())
    new_id = rpc("newTerminal", project=project["id"], worktree=worktree["id"])
    assert new_id != terminal
    assert len(terminals()) == before + 1
    assert rpc("workspace", version=PROTOCOL)["selection"] != new_id, "A terminal created from the phone does not take the Mac's selection"
    print("PASS shared Git diff and new remote terminal", flush=True)

    with watch(terminal) as sock:
        (repo / "pushed.txt").write_text("Change pushed to the phone\n")
        deadline = time.monotonic() + 10
        while "repositoryChanged" not in read(sock, notifications=True):
            assert time.monotonic() < deadline, "No repository change notification"
    print("PASS repository changes pushed on the watch stream", flush=True)

    with connect(timeout=5) as sock:
        sock.sendall(struct.pack("!I", 5 * 1024 * 1024))
        try:
            assert sock.recv(1) == b""
        except (ssl.SSLEOFError, ConnectionError):
            pass
    print("PASS oversized frame rejected", flush=True)
    launcher = root / "bin" / "claude"
    launcher.parent.mkdir()
    launcher.write_bytes((Path(__file__).resolve().parent / "fixtures/claude-terminal.py").read_bytes())
    launcher.chmod(0o755)
    agent = bridge("terminal.create", projectID=project["id"], worktreeID=worktree["id"], name="Claude fixture",
                   command=[str(launcher)])["terminalID"]
    with watch(agent) as sock:
        messages = []
        def apply(event):
            if "terminal" not in event:
                return False
            snapshot = event["terminal"]["_0"]
            del messages[:snapshot["transcriptDropped"]]
            messages[snapshot["transcriptStart"]:] = snapshot["transcript"]
            if append := snapshot.get("transcriptAppend"):
                assert messages[-1]["id"] == append["id"]
                messages[-1]["text"] += append["text"]
            return snapshot.get("chatSource") == "claude"
        while not (apply(read(sock)) and any("CLAUDE_FIXTURE_READY" in m["text"] for m in messages)):
            pass
        prompt = "First line\nSecond line 👋"
        request_id = str(uuid.uuid4()).upper()
        send(sock, {"streamInput": dict(request=request_id, terminal=agent,
                                       data=base64.b64encode((prompt + "\r").encode()).decode(), message=prompt)})
        ack = False
        while not (ack and any("STRUCTURED_REPLY" in m["text"] for m in messages)):
            event = read(sock)
            if "inputResult" in event:
                assert not event["inputResult"].get("error"), event
                ack = event["inputResult"]["request"] == request_id
            apply(event)
        assert [m["text"] for m in messages if m["kind"] == "input"] == [prompt], messages
        assert any(m.get("toolState") == "completed" and m["title"] == "Read" for m in messages), messages
        assert all("TUI_NOISE" not in m["text"] for m in messages)
    print("PASS Claude structured journal over TCP, multiline paste, no duplicate input or TUI scraping", flush=True)

    codex_launcher = root / "bin" / "codex"
    codex_launcher.write_bytes((Path(__file__).resolve().parent / "fixtures/codex-terminal.py").read_bytes())
    codex_launcher.chmod(0o755)
    rollouts = root / "codex"
    rollouts.mkdir()
    codex = bridge("terminal.create", projectID=project["id"], worktreeID=worktree["id"], name="Codex fixture",
                   command=["/usr/bin/env", f"AGENTUI_CODEX_FIXTURE_DIR={rollouts}", str(codex_launcher)])["terminalID"]
    with watch(codex) as sock:
        messages = []
        def apply(event):
            if "terminal" not in event:
                return False
            snapshot = event["terminal"]["_0"]
            del messages[:snapshot["transcriptDropped"]]
            messages[snapshot["transcriptStart"]:] = snapshot["transcript"]
            if append := snapshot.get("transcriptAppend"):
                messages[-1]["text"] += append["text"]
            return snapshot["isChat"] and snapshot.get("chatSource") == "codex"
        deadline = time.monotonic() + 20
        while not (apply(read(sock)) and any("CODEX_FIXTURE_READY" in m["text"] for m in messages)):
            assert time.monotonic() < deadline, "Codex journal never reached the phone"
        request_id = str(uuid.uuid4()).upper()
        send(sock, {"streamInput": dict(request=request_id, terminal=codex,
                                       data=base64.b64encode("Lis le fichier\r".encode()).decode(), message="Lis le fichier")})
        while not any("CODEX_STRUCTURED_REPLY" in m["text"] for m in messages):
            assert time.monotonic() < deadline + 20, "Codex reply never reached the phone"
            apply(read(sock))
        assert [m["text"] for m in messages if m["kind"] == "input"] == ["Lis le fichier"], messages
        assert any(m.get("toolState") == "completed" and m["title"] == "exec" and m["text"] == "Bonjour du Mac" for m in messages), messages
        assert all("TUI_NOISE" not in m["text"] and "environment_context" not in m["text"] for m in messages), messages
    print("PASS Codex structured rollout over TCP, tool output, no injected context or TUI scraping", flush=True)

    print("Fixture:", root, flush=True)
    if "--hold" in sys.argv:
        print("Host ready for simulator testing with pairing code", PAIRING_CODE, "; interrupt to stop.", flush=True)
        while True:
            time.sleep(1)
finally:
    if app and app.poll() is None:
        if instance:
            try:
                bridge("debug.stop")
                app.wait(timeout=10)
            except Exception:
                app.terminate()
        else:
            app.terminate()
