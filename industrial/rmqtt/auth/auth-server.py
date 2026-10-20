#!/usr/bin/env python3
"""HTTP authentication and authorization service for the RMQTT brokers (rmqtt-auth-http plugin).

Replaces the Artemis login (user artemis, role amq with every permission on every address):

    POST /mqtt/auth   form: clientid, username, password, protocol    -> body "allow" or "deny"
    POST /mqtt/acl    form: access (1 subscribe, 2 publish), username, clientid, ipaddr, topic -> "allow" or "deny"
    GET  /health      -> "ok"

The users file is JSON and is read again when it changes:

    {"users": {
        "artemis": {"password": "artemis", "superuser": true},
        "gateway": {"password": "sha256:<hex digest>", "publish": ["iot/#"], "subscribe": ["iot/#"]}
    }}

- password: clear text, or "sha256:" and the hex digest of the password.
- superuser: true skips the topic checks (the broker honours the X-Superuser header on the allow answer).
- publish and subscribe: topic filters the user may use. A subscription is allowed when the filter it asks for is
  covered by one of the allowed filters ("iot/#" covers "iot/a/+"; "iot/+" does not cover "iot/#").

Only the Python standard library is used. Environment: USERS_FILE (default /run/secrets/rmqtt_users), PORT (8080).
"""
import hashlib
import hmac
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

USERS_FILE = os.environ.get('USERS_FILE', '/run/secrets/rmqtt_users')
PORT = int(os.environ.get('PORT', '8080'))

_cache = {'mtime': None, 'users': {}}


def load_users():
    """The users of the file, read again only when its modification time changed."""
    try:
        mtime = os.stat(USERS_FILE).st_mtime_ns
    except OSError:
        return {}
    if mtime != _cache['mtime']:
        try:
            with open(USERS_FILE, encoding='utf-8') as f:
                _cache['users'] = json.load(f).get('users', {})
            _cache['mtime'] = mtime
        except (OSError, ValueError) as e:
            print(f'cannot read {USERS_FILE}: {e}', file=sys.stderr, flush=True)
            return _cache['users']
    return _cache['users']


def password_matches(stored, given):
    if stored.startswith('sha256:'):
        digest = hashlib.sha256(given.encode('utf-8')).hexdigest()
        return hmac.compare_digest(stored[7:].lower(), digest)
    return hmac.compare_digest(stored.encode('utf-8'), given.encode('utf-8'))


def filter_covers(allowed, requested):
    """True when every topic matched by the filter 'requested' is matched by the filter 'allowed'."""
    a, r = allowed.split('/'), requested.split('/')
    i = 0
    while i < len(a):
        if a[i] == '#':
            return True
        if i >= len(r):
            return False
        if r[i] == '#':
            return False
        if a[i] != '+' and a[i] != r[i]:
            return False
        i += 1
    return len(r) == len(a)


def authenticate(users, username, password):
    user = users.get(username) if username else None
    return user is not None and isinstance(user.get('password'), str) and password_matches(user['password'], password)


def authorize(users, username, access, topic):
    user = users.get(username)
    if user is None:
        return False
    if user.get('superuser'):
        return True
    key = 'subscribe' if access == '1' else 'publish' if access == '2' else None
    return key is not None and any(filter_covers(f, topic) for f in user.get(key, []))


class Handler(BaseHTTPRequestHandler):
    def reply(self, body, extra=None):
        data = body.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(data)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/health':
            self.reply('ok')
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get('Content-Length') or 0)
        form = {k: v[0] for k, v in parse_qs(self.rfile.read(length).decode('utf-8'), keep_blank_values=True).items()}
        users = load_users()
        if self.path == '/mqtt/auth':
            username = form.get('username', '')
            if authenticate(users, username, form.get('password', '')):
                self.reply('allow', {'X-Superuser': 'true'} if users[username].get('superuser') else None)
            else:
                self.reply('deny')
        elif self.path == '/mqtt/acl':
            self.reply('allow' if authorize(users, form.get('username', ''), form.get('access', ''), form.get('topic', '')) else 'deny')
        else:
            self.send_error(404)

    def log_message(self, fmt, *args):
        print('%s %s' % (self.address_string(), fmt % args), flush=True)


if __name__ == '__main__':
    print(f'rmqtt auth service on :{PORT}, users file {USERS_FILE}', flush=True)
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
