import io
import json
import os
import struct
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock

# Run as `python3 -I host/test_host.py`. Isolated mode does not add the script dir to sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import protly_host as h  # noqa: E402


def make_home(key='sk-ant-test-123', ws='wrkspc_test'):
    d = tempfile.mkdtemp()
    base = os.path.join(d, '.config', 'anthropic')
    os.makedirs(os.path.join(base, 'configs'))
    if key is not None:
        with open(os.path.join(base, 'api-key'), 'w') as f:
            f.write(key + '\n')
    with open(os.path.join(base, 'configs', 'default.json'), 'w') as f:
        json.dump({'workspace_id': ws}, f)
    return d


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


if __name__ == '__main__':
    unittest.main()
