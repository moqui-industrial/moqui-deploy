"""Tests of the RMQTT authentication service. Run: python3 -m unittest industrial/rmqtt/auth/test_auth_server.py"""
import hashlib
import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

USERS = {'users': {
    'admin': {'password': 'admin-pw', 'superuser': True},
    'gateway': {'password': 'sha256:' + hashlib.sha256(b'gw-pw').hexdigest(),
                'publish': ['iot/parameters/in', 'iot/+/status'], 'subscribe': ['iot/#']},
}}


class AuthServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False)
        json.dump(USERS, cls.tmp)
        cls.tmp.close()
        os.environ['USERS_FILE'] = cls.tmp.name
        import importlib.util
        spec = importlib.util.spec_from_file_location('auth_server', os.path.join(os.path.dirname(__file__), 'auth-server.py'))
        cls.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.mod)
        cls.httpd = ThreadingHTTPServer(('127.0.0.1', 0), cls.mod.Handler)
        cls.port = cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        os.unlink(cls.tmp.name)

    def post(self, path, **form):
        data = '&'.join(f'{k}={v}' for k, v in form.items()).encode()
        req = urllib.request.Request(f'http://127.0.0.1:{self.port}{path}', data=data, method='POST')
        with urllib.request.urlopen(req) as r:
            return r.read().decode(), r.headers.get('X-Superuser')

    def test_auth(self):
        self.assertEqual(self.post('/mqtt/auth', username='admin', password='admin-pw'), ('allow', 'true'))
        self.assertEqual(self.post('/mqtt/auth', username='gateway', password='gw-pw'), ('allow', None))
        for u, p in [('admin', 'wrong'), ('gateway', 'admin-pw'), ('nobody', 'x'), ('', ''), ('gateway', '')]:
            self.assertEqual(self.post('/mqtt/auth', username=u, password=p)[0], 'deny', (u, p))

    def test_acl(self):
        a = lambda user, access, topic: self.post('/mqtt/acl', username=user, access=access, topic=topic)[0]
        self.assertEqual(a('gateway', '2', 'iot/parameters/in'), 'allow')
        self.assertEqual(a('gateway', '2', 'iot/dev1/status'), 'allow')
        self.assertEqual(a('gateway', '2', 'iot/dev1/cmd'), 'deny')
        self.assertEqual(a('gateway', '1', 'iot/#'), 'allow')
        self.assertEqual(a('gateway', '1', 'iot/a/+'), 'allow')
        self.assertEqual(a('gateway', '1', '#'), 'deny')
        self.assertEqual(a('gateway', '1', 'other/x'), 'deny')
        self.assertEqual(a('nobody', '2', 'iot/x'), 'deny')

    def test_filter_covers(self):
        c = self.mod.filter_covers
        self.assertTrue(c('iot/#', 'iot'))        # '#' also matches the parent level
        self.assertTrue(c('iot/+/x', 'iot/a/x'))
        self.assertFalse(c('iot/+', 'iot/#'))
        self.assertFalse(c('iot/+', 'iot/a/b'))
        self.assertFalse(c('iot/a/b', 'iot/a'))

    def test_health_and_not_found(self):
        with urllib.request.urlopen(f'http://127.0.0.1:{self.port}/health') as r:
            self.assertEqual(r.read(), b'ok')
        with self.assertRaises(urllib.error.HTTPError):
            urllib.request.urlopen(f'http://127.0.0.1:{self.port}/other')


if __name__ == '__main__':
    unittest.main()
