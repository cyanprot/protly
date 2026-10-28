#!/usr/bin/python3
"""ig-translate native messaging host.

Chrome sends {id, body} messages on stdin. Each body is sent to the Anthropic Messages API
and the reply {id, status, retry_after, body} is written to stdout. Messages in both
directions are UTF-8 JSON preceded by a 32-bit length in native byte order.
The API key never leaves this process; nothing here logs it.
"""
import json
import os
import struct
import sys
import threading
import urllib.error
import urllib.request

API_URL = 'https://api.anthropic.com/v1/messages'
TIMEOUT_S = 240  # Opus hard (effort high, 32k tokens, non-streaming) can take minutes
MAX_REPLY = 1024 * 1024  # Chrome rejects host messages larger than 1 MB

_out_lock = threading.Lock()
EOF = object()  # distinct from a JSON null frame


def read_message(stream):
    raw = stream.read(4)
    if len(raw) < 4:
        return EOF
    (n,) = struct.unpack('=I', raw)
    data = stream.read(n)
    if len(data) < n:
        return EOF
    return json.loads(data.decode('utf-8'))


def encode_message(obj):
    data = json.dumps(obj).encode('utf-8')  # ASCII escapes: a lone surrogate cannot break encoding
    return struct.pack('=I', len(data)) + data


def local_error(req_id, kind, message):
    return {'id': req_id, 'status': 0, 'retry_after': None,
            'body': {'error': {'type': kind, 'message': message}}}


def write_message(stream, obj):
    data = encode_message(obj)
    if len(data) - 4 > MAX_REPLY:
        data = encode_message(local_error(obj.get('id'), 'host_error', 'reply larger than 1 MB'))
    with _out_lock:
        stream.write(data)
        stream.flush()


def build_headers(home):
    base = os.path.join(home, '.config', 'anthropic')
    with open(os.path.join(base, 'api-key')) as f:
        key = f.read().strip()
    with open(os.path.join(base, 'configs', 'default.json')) as f:
        workspace = json.load(f).get('workspace_id')
    headers = {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
    }
    if workspace:
        headers['anthropic-workspace-id'] = workspace
    return headers


def handle(req, home, urlopen=urllib.request.urlopen):
    req_id = req.get('id')
    try:
        headers = build_headers(home)
    except (OSError, ValueError) as e:
        where = getattr(e, 'filename', None) or '~/.config/anthropic'
        return local_error(req_id, 'host_config', f'cannot read API key config ({type(e).__name__}: {where})')
    request = urllib.request.Request(API_URL, data=json.dumps(req['body']).encode('utf-8'),
                                     headers=headers, method='POST')
    try:
        with urlopen(request, timeout=TIMEOUT_S) as resp:
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


def main():
    home = os.path.expanduser('~')
    stdin, stdout = sys.stdin.buffer, sys.stdout.buffer
    while True:
        try:
            req = read_message(stdin)
        except ValueError:
            continue  # unparseable JSON has no id to reply to; the frame was consumed, keep reading
        if req is EOF:
            break  # Chrome closed the port
        if not isinstance(req, dict):
            continue  # no id to reply to
        threading.Thread(target=lambda r=req: write_message(stdout, safe_handle(r, home)), daemon=True).start()


if __name__ == '__main__':
    main()
