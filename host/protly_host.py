#!/usr/bin/python3
"""protly native messaging host.

Chrome sends {id, body} messages on stdin. Each body is sent to the Anthropic Messages API
and the reply {id, status, retry_after, body} is written to stdout. Messages in both
directions are UTF-8 JSON preceded by a 32-bit length in native byte order.
A {id, ping: true} message is answered locally with {id, ping: {ok, key_present, key_shared, workspace_header}}.
The API key never leaves this process; nothing here logs it.
"""
import json
import os
import stat
import struct
import sys
import threading
import urllib.error
import urllib.request

API_URL = 'https://api.anthropic.com/v1/messages'
TIMEOUT_S = 240  # Opus hard (effort high, 32k tokens, non-streaming) can take minutes
MAX_REPLY = 1024 * 1024  # Chrome rejects host messages larger than 1 MB
MAX_REQUEST = 16 * 1024 * 1024  # far above any request the extension builds (its messages are size-checked)

_out_lock = threading.Lock()
EOF = object()  # distinct from a JSON null frame
TOO_LARGE = object()  # a frame length over MAX_REQUEST: never allocated


def read_message(stream):
    raw = stream.read(4)
    if len(raw) < 4:
        return EOF
    (n,) = struct.unpack('=I', raw)
    if n > MAX_REQUEST:
        return TOO_LARGE
    data = stream.read(n)
    if len(data) < n:
        return EOF
    return json.loads(data.decode('utf-8'))


def encode_message(obj):
    # ASCII escapes: a lone surrogate cannot break encoding. allow_nan=False: NaN or Infinity in an API body would
    # be invalid JSON, and Chrome drops the port (and every request in flight) on one bad frame.
    data = json.dumps(obj, allow_nan=False).encode('utf-8')
    return struct.pack('=I', len(data)) + data


def local_error(req_id, kind, message):
    return {'id': req_id, 'status': 0, 'retry_after': None,
            'body': {'error': {'type': kind, 'message': message}}}


def write_message(stream, obj):
    try:
        data = encode_message(obj)
    except (ValueError, RecursionError):  # NaN, or an API body nested too deep to encode: reply, never hang
        data = encode_message(local_error(obj.get('id'), 'host_error', 'reply is not valid JSON'))
    if len(data) - 4 > MAX_REPLY:
        data = encode_message(local_error(obj.get('id'), 'host_error', 'reply larger than 1 MB'))
    with _out_lock:
        stream.write(data)
        stream.flush()


def build_headers(home):
    base = os.path.join(home, '.config', 'anthropic')
    with open(os.path.join(base, 'api-key')) as f:
        key = f.read().strip()
    workspace = None
    try:  # optional, like ping() reports it
        with open(os.path.join(base, 'configs', 'default.json')) as f:
            workspace = json.load(f).get('workspace_id')
    except (OSError, ValueError, AttributeError):
        pass
    headers = {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
    }
    if workspace:
        headers['anthropic-workspace-id'] = workspace
    return headers


def key_shared(path):
    """True when the group or others may read or write the key file (through a symlink too). Mode only: no read."""
    try:
        mode = os.stat(path).st_mode
    except OSError:
        return False
    return bool(mode & (stat.S_IRWXG | stat.S_IRWXO))


def ping(home):
    """Local health check for the options page. Reports whether the key and workspace exist, never their values."""
    base = os.path.join(home, '.config', 'anthropic')
    shared = key_shared(os.path.join(base, 'api-key'))
    key_present = False
    try:
        with open(os.path.join(base, 'api-key')) as f:
            key_present = bool(f.read().strip())
    except OSError:
        pass
    workspace = False
    try:
        with open(os.path.join(base, 'configs', 'default.json')) as f:
            workspace = bool(json.load(f).get('workspace_id'))
    except (OSError, ValueError, AttributeError):
        pass
    return {'ok': True, 'key_present': key_present, 'key_shared': shared, 'workspace_header': workspace}


def handle(req, home, urlopen=None):
    req_id = req.get('id')
    if req.get('ping'):
        return {'id': req_id, 'ping': ping(home)}
    try:
        headers = build_headers(home)
    except (OSError, ValueError) as e:
        where = getattr(e, 'filename', None) or '~/.config/anthropic'
        return local_error(req_id, 'host_config', f'cannot read API key config ({type(e).__name__}: {where})')
    request = urllib.request.Request(API_URL, data=json.dumps(req['body']).encode('utf-8'),
                                     headers=headers, method='POST')
    try:
        with (urlopen or urllib.request.urlopen)(request, timeout=TIMEOUT_S) as resp:  # looked up per call: tests patch it
            return {'id': req_id, 'status': resp.status,
                    'retry_after': resp.headers.get('retry-after'), 'body': json.loads(resp.read())}
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except ValueError:
            body = {}
        return {'id': req_id, 'status': e.code, 'retry_after': e.headers.get('retry-after'), 'body': body}
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        reason = getattr(e, 'reason', None) or e
        kind = 'host_timeout' if isinstance(reason, TimeoutError) else 'host_network'
        return local_error(req_id, kind, f'network: {reason or type(e).__name__}')


def safe_handle(req, home):
    try:
        return handle(req, home)
    except Exception as e:  # never let one bad request kill the host
        return local_error(req.get('id') if isinstance(req, dict) else None, 'host_error', type(e).__name__)


def serve(stdin, stdout, home):
    """Reads frames until EOF; each request is answered on its own thread. Returns the threads (tests join them)."""
    threads = []
    while True:
        try:
            req = read_message(stdin)
        except (ValueError, RecursionError):
            continue  # unparseable or absurdly nested JSON has no id to reply to; the frame was consumed
        if req is EOF:
            break  # Chrome closed the port
        if req is TOO_LARGE:
            # The payload cannot be skipped without reading it, and nothing the extension builds is this big.
            # Exit: Chrome sees the port close and fails the pending requests at once instead of timing out.
            sys.stderr.write('protly host: request frame over the size limit; exiting\n')
            break
        if not isinstance(req, dict):
            continue  # no id to reply to
        t = threading.Thread(target=lambda r=req: write_message(stdout, safe_handle(r, home)), daemon=True)
        t.start()
        threads = [x for x in threads if x.is_alive()] + [t]  # a long-lived host keeps only running threads
    return threads


def main():
    serve(sys.stdin.buffer, sys.stdout.buffer, os.path.expanduser('~'))


if __name__ == '__main__':
    main()
