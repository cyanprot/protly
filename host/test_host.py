import http.client
import io
import json
import os
import shutil
import subprocess
import struct
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock

# Run as `python3 -I host/test_host.py`. Isolated mode does not add the script dir to sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import protly_host as h  # noqa: E402


TEMP_DIRS = []


def tearDownModule():
    for d in TEMP_DIRS:
        shutil.rmtree(d, True)


def make_home(key='sk-ant-test-123', ws='wrkspc_test'):
    d = tempfile.mkdtemp()
    TEMP_DIRS.append(d)
    base = os.path.join(d, '.config', 'anthropic')
    os.makedirs(os.path.join(base, 'configs'))
    if key is not None:
        with open(os.path.join(base, 'api-key'), 'w') as f:
            f.write(key + '\n')
    with open(os.path.join(base, 'configs', 'default.json'), 'w') as f:
        json.dump({'workspace_id': ws}, f)
    return d


def offline(urlopen):
    """safe_handle calls handle() without urlopen, which then uses urllib.request.urlopen: replace that."""
    return mock.patch.object(h.urllib.request, 'urlopen', urlopen)


class FakeResp:
    def __init__(self, status, body, headers=None):
        self.status = status
        self._b = json.dumps(body).encode()
        self.headers = headers or {}

    def read(self):
        return self._b

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Framing(unittest.TestCase):
    def test_round_trip(self):
        msg = {'id': 7, 'body': {'text': '안녕 привет'}}
        buf = io.BytesIO(h.encode_message(msg))
        self.assertEqual(h.read_message(buf), msg)
        self.assertIs(h.read_message(buf), h.EOF)

    def test_null_frame_is_not_eof(self):
        buf = io.BytesIO(h.encode_message(None))
        self.assertIsNone(h.read_message(buf))

    def test_lone_surrogate_encodes(self):
        data = h.encode_message({'t': '\ud83d'})
        self.assertEqual(h.read_message(io.BytesIO(data)), {'t': '\ud83d'})

    def test_length_is_utf8_byte_count(self):
        data = h.encode_message({'t': '안'})
        (n,) = struct.unpack('=I', data[:4])
        self.assertEqual(n, len(data) - 4)

    def test_write_message(self):
        out = io.BytesIO()
        h.write_message(out, {'id': 1})
        out.seek(0)
        self.assertEqual(h.read_message(out), {'id': 1})

    def test_oversized_reply_becomes_host_error(self):
        out = io.BytesIO()
        h.write_message(out, {'id': 9, 'status': 200, 'body': {'x': 'a' * (h.MAX_REPLY + 1)}})
        out.seek(0)
        r = h.read_message(out)
        self.assertEqual(r['id'], 9)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_error')


class Headers(unittest.TestCase):
    def test_reads_key_and_workspace(self):
        hd = h.build_headers(make_home())
        self.assertEqual(hd['x-api-key'], 'sk-ant-test-123')
        self.assertEqual(hd['anthropic-workspace-id'], 'wrkspc_test')
        self.assertEqual(hd['anthropic-version'], '2023-06-01')
        self.assertEqual(hd['content-type'], 'application/json')
        names = {k.lower() for k in hd}
        self.assertNotIn('origin', names)
        self.assertNotIn('anthropic-dangerous-direct-browser-access', names)

    def test_missing_workspace_config_is_no_header(self):
        home = make_home()
        os.remove(os.path.join(home, '.config', 'anthropic', 'configs', 'default.json'))
        hd = h.build_headers(home)
        self.assertNotIn('anthropic-workspace-id', hd)

    def test_workspace_optional(self):
        hd = h.build_headers(make_home(ws=None))
        self.assertNotIn('anthropic-workspace-id', hd)


class Handle(unittest.TestCase):
    def test_missing_key_file(self):
        op = mock.Mock()
        r = h.handle({'id': 3, 'body': {}}, make_home(key=None), urlopen=op)
        self.assertEqual(r['id'], 3)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_config')
        op.assert_not_called()

    def test_success(self):
        op = mock.Mock(return_value=FakeResp(200, {'content': []}))
        r = h.handle({'id': 1, 'body': {'model': 'm'}}, make_home(), urlopen=op)
        self.assertEqual(r, {'id': 1, 'status': 200, 'retry_after': None, 'body': {'content': []}})
        req = op.call_args[0][0]
        self.assertEqual(req.full_url, h.API_URL)
        self.assertEqual(req.get_method(), 'POST')
        self.assertEqual(json.loads(req.data), {'model': 'm'})
        self.assertEqual(req.get_header('X-api-key'), 'sk-ant-test-123')
        self.assertEqual(op.call_args[1]['timeout'], h.TIMEOUT_S)

    def test_http_error_keeps_status_retry_after_and_body(self):
        err = urllib.error.HTTPError(h.API_URL, 429, 'rate', {'retry-after': '3'},
                                     io.BytesIO(b'{"error":{"message":"slow"}}'))
        r = h.handle({'id': 2, 'body': {}}, make_home(), urlopen=mock.Mock(side_effect=err))
        self.assertEqual(r['status'], 429)
        self.assertEqual(r['retry_after'], '3')
        self.assertEqual(r['body']['error']['message'], 'slow')

    def test_network_error(self):
        op = mock.Mock(side_effect=urllib.error.URLError('down'))
        r = h.handle({'id': 4, 'body': {}}, make_home(), urlopen=op)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_network')

    def test_socket_timeout_is_host_timeout(self):
        for exc in (TimeoutError('timed out'), urllib.error.URLError(TimeoutError('timed out'))):
            op = mock.Mock(side_effect=exc)
            r = h.handle({'id': 4, 'body': {}}, make_home(), urlopen=op)
            self.assertEqual(r['body']['error']['type'], 'host_timeout')

    def test_errors_never_contain_the_key(self):
        op = mock.Mock(side_effect=urllib.error.URLError('down'))
        for home in (make_home(key=None), make_home()):
            r = h.handle({'id': 5, 'body': {}}, home, urlopen=op)
            self.assertNotIn('sk-ant-test-123', json.dumps(r))

    def test_safe_handle_catches_bad_request(self):
        r = h.safe_handle({'id': 6}, make_home())
        self.assertEqual(r['id'], 6)
        self.assertEqual(r['status'], 0)
        self.assertEqual(r['body']['error']['type'], 'host_error')


class Ping(unittest.TestCase):
    def test_reports_key_and_workspace_without_calling_the_api(self):
        op = mock.Mock()
        r = h.handle({'id': 11, 'ping': True}, make_home(), urlopen=op)
        self.assertEqual(r, {'id': 11, 'ping': {'ok': True, 'key_present': True, 'workspace_header': True}})
        op.assert_not_called()

    def test_missing_key(self):
        r = h.handle({'id': 12, 'ping': True}, make_home(key=None), urlopen=mock.Mock())
        self.assertEqual(r['ping'], {'ok': True, 'key_present': False, 'workspace_header': True})

    def test_empty_key_counts_as_missing(self):
        r = h.handle({'id': 13, 'ping': True}, make_home(key='  '), urlopen=mock.Mock())
        self.assertFalse(r['ping']['key_present'])

    def test_missing_workspace(self):
        r = h.handle({'id': 14, 'ping': True}, make_home(ws=None), urlopen=mock.Mock())
        self.assertEqual(r['ping'], {'ok': True, 'key_present': True, 'workspace_header': False})

    def test_reply_never_contains_the_key(self):
        r = h.safe_handle({'id': 15, 'ping': True}, make_home())
        self.assertNotIn('sk-ant-test-123', json.dumps(r))


class HostileInput(unittest.TestCase):
    """Malformed frames and bodies: the host keeps serving, never sends Chrome invalid JSON, never echoes the key."""

    def serve(self, frames):
        out = io.BytesIO()
        threads = h.serve(io.BytesIO(b''.join(frames)), out, make_home())
        for t in threads:
            t.join(5)
        out.seek(0)
        replies = []
        while (r := h.read_message(out)) is not h.EOF:
            replies.append(r)
        return replies

    def test_oversized_frame_length_is_not_read(self):
        frame = struct.pack('=I', h.MAX_REQUEST + 1)
        stream = mock.Mock()
        stream.read.side_effect = [frame]
        self.assertIs(h.read_message(stream), h.TOO_LARGE)
        stream.read.assert_called_once_with(4)  # the payload is never allocated

    def test_oversized_frame_stops_the_host(self):
        big = struct.pack('=I', h.MAX_REQUEST + 1) + b'{}'
        self.assertEqual(self.serve([big, h.encode_message({'id': 1, 'ping': True})]), [])

    def test_deeply_nested_json_does_not_kill_the_host(self):
        deep = b'[' * 200000 + b']' * 200000
        frames = [struct.pack('=I', len(deep)) + deep, h.encode_message({'id': 2, 'ping': True})]
        replies = self.serve(frames)
        self.assertEqual([r['id'] for r in replies], [2])

    def test_garbage_frames_are_skipped(self):
        bad = [b'\xff\xfe', b'{"id": 1,', b'[]', b'"x"', b'null']
        frames = [struct.pack('=I', len(b)) + b for b in bad] + [h.encode_message({'id': 3, 'ping': True})]
        self.assertEqual([r['id'] for r in self.serve(frames)], [3])

    def test_nan_in_an_api_body_never_reaches_chrome_as_invalid_json(self):
        class Resp(FakeResp):
            def read(self):
                return b'{"content": NaN, "usage": {"input_tokens": Infinity}}'
        r = h.handle({'id': 4, 'body': {}}, make_home(), urlopen=mock.Mock(return_value=Resp(200, {})))
        out = io.BytesIO()
        h.write_message(out, r)
        raw = out.getvalue()[4:].decode()
        reply = json.loads(raw, parse_constant=lambda c: self.fail(f'{c} sent to Chrome'))
        self.assertEqual(reply['id'], 4)
        self.assertEqual(reply['status'], 0)
        self.assertEqual(reply['body']['error']['type'], 'host_error')

    def test_deeply_nested_api_body_gets_a_reply_not_a_hang(self):
        body = []
        for _ in range(100000):  # deeper than json.dumps can encode (its C encoder allows a few thousand)
            body = [body]
        out = io.BytesIO()
        h.write_message(out, {'id': 8, 'status': 200, 'body': body})
        out.seek(0)
        r = h.read_message(out)
        self.assertEqual((r['id'], r['status'], r['body']['error']['type']), (8, 0, 'host_error'))

    def test_write_message_survives_an_unencodable_reply(self):
        out = io.BytesIO()
        real = h.encode_message
        with mock.patch.object(h, 'encode_message', side_effect=[RecursionError(), real(h.local_error(9, 'host_error', 'x'))]):
            h.write_message(out, {'id': 9, 'status': 200, 'body': {}})
        out.seek(0)
        r = h.read_message(out)
        self.assertEqual((r['id'], r['status'], r['body']['error']['type']), (9, 0, 'host_error'))

    def test_non_json_2xx_body_is_a_host_error_without_the_key(self):
        class Resp(FakeResp):
            def read(self):
                return b'<html>captive portal sk-ant-test-123</html>'
        with offline(mock.Mock(return_value=Resp(200, {}))):
            r = h.safe_handle({'id': 5, 'body': {}}, make_home())
        self.assertEqual(r['body']['error']['type'], 'host_error')
        self.assertNotIn('sk-ant-test-123', json.dumps(r))

    def test_a_key_that_breaks_the_header_never_appears_in_the_reply(self):
        home = make_home(key='sk-ant-test\n-123')  # http.client's ValueError text quotes the header value

        def validate_headers_only(request, timeout):  # real http.client header checks, no connection
            conn = http.client.HTTPSConnection('api.anthropic.com')
            conn.putrequest('POST', '/v1/messages')
            for k, v in request.header_items():
                conn.putheader(k, v)
            self.fail('the header was accepted')
        with offline(validate_headers_only):
            r = h.safe_handle({'id': 6, 'body': {'model': 'x'}}, home)
        self.assertEqual(r['status'], 0)
        self.assertNotIn('sk-ant-test', json.dumps(r))


class Install(unittest.TestCase):
    """install.sh writes a valid manifest whatever the checkout path holds, and only for a real extension id."""

    def run_install(self, dirname, ext_id='a' * 32):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, True)
        src = os.path.join(tmp, dirname)
        os.makedirs(src)
        here = os.path.dirname(os.path.abspath(__file__))
        for f in ('install.sh', 'protly_host.py'):
            shutil.copy(os.path.join(here, f), os.path.join(src, f))
        env = {'HOME': tmp, 'PATH': os.environ.get('PATH', '/usr/bin:/bin')}
        p = subprocess.run(['bash', os.path.join(src, 'install.sh'), ext_id], env=env, capture_output=True, text=True)
        manifest = os.path.join(tmp, '.config', 'google-chrome', 'NativeMessagingHosts', 'com.northprot.protly.json')
        return p, manifest, src

    def test_quotes_and_backslashes_in_the_path_stay_inside_the_path(self):
        p, manifest, src = self.run_install('pro"tly\\x", "allowed_origins": ["evil"], "y": "')
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(manifest) as f:
            m = json.load(f)
        self.assertEqual(m['path'], os.path.join(src, 'protly_host.py'))
        self.assertEqual(m['allowed_origins'], ['chrome-extension://' + 'a' * 32 + '/'])
        self.assertEqual(sorted(m), ['allowed_origins', 'description', 'name', 'path', 'type'])

    def test_a_failed_write_keeps_the_old_manifest(self):
        p, manifest, src = self.run_install('protly')
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(manifest) as f:
            before = f.read()
        tmp = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(manifest))))
        bin_dir = os.path.join(tmp, 'bin')
        os.makedirs(bin_dir)
        with open(os.path.join(bin_dir, 'python3'), 'w') as f:
            f.write('#!/bin/sh\nexit 3\n')
        os.chmod(os.path.join(bin_dir, 'python3'), 0o755)
        env = {'HOME': tmp, 'PATH': bin_dir + ':' + os.environ.get('PATH', '/usr/bin:/bin')}
        q = subprocess.run(['bash', os.path.join(src, 'install.sh'), 'a' * 32], env=env, capture_output=True, text=True)
        self.assertNotEqual(q.returncode, 0)
        with open(manifest) as f:
            self.assertEqual(f.read(), before)
        self.assertEqual([n for n in os.listdir(os.path.dirname(manifest)) if n.startswith('.')], [])

    def test_rejects_a_bad_extension_id(self):
        p, manifest, _ = self.run_install('protly', ext_id='a' * 31 + '"')
        self.assertNotEqual(p.returncode, 0)
        self.assertFalse(os.path.exists(manifest))


if __name__ == '__main__':
    unittest.main()
