import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from email.message import EmailMessage

spec = importlib.util.spec_from_file_location('qq_bridge', Path(__file__).parents[1] / 'Sources/AgentEmail/Resources/qq_bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def message(subject='[AGENT] 测试', sender='me@qq.com', automated=False):
    m = EmailMessage()
    m['Subject'] = subject
    m['From'] = sender
    m['To'] = 'me@qq.com'
    m['Message-ID'] = '<test-id@qq.com>'
    if automated: m['Auto-Submitted'] = 'auto-replied'
    m.set_content('请回复测试结果。')
    return m


class FakeIMAP:
    def __init__(self, *a, **kw): pass
    def __enter__(self): return self
    def __exit__(self, *a): pass
    def login(self, *a): return 'OK', []
    def select(self, *a, **kw): return 'OK', [b'3']
    def response(self, *a): return 'UIDVALIDITY', [b'9']
    def uid(self, action, *args):
        if action == 'search': return 'OK', [b'1 2 3']
        if action == 'fetch': return 'OK', [(b'metadata', message().as_bytes()), b')']
        raise AssertionError(action)


class FakeSMTP:
    sent = []
    def __init__(self, *a, **kw): pass
    def __enter__(self): return self
    def __exit__(self, *a): pass
    def login(self, *a): pass
    def send_message(self, msg, **kw): self.sent.append((msg, kw))


class QQTests(unittest.TestCase):
    def setUp(self): FakeSMTP.sent = []
    def request(self, action, **kw):
        req = dict(action=action, address='me@qq.com', secret='fixture-only')
        req.update(kw)
        with patch.object(bridge.imaplib, 'IMAP4_SSL', FakeIMAP), patch.object(bridge.smtplib, 'SMTP_SSL', FakeSMTP):
            return bridge.handle(req)

    def test_unicode(self):
        result = bridge.parse_message(message().as_bytes(), 3, '9')
        self.assertEqual(result['subject'], '[AGENT] 测试')
        self.assertIn('请回复', result['body'])
        self.assertTrue(bridge.should_trigger(result, 'me@qq.com', '[AGENT]'))

    def test_ignore_replies_and_other_senders(self):
        for msg in (message(automated=True), message(sender='other@qq.com'), message(subject='Re: [AGENT] 测试'), message(subject='[AGENT] ')):
            self.assertFalse(bridge.should_trigger(bridge.parse_message(msg.as_bytes(), 3, '9'), 'me@qq.com', '[AGENT]'))

    def test_connect_validates_without_sending(self):
        result = self.request('connect')
        self.assertEqual(result['cursor'], 3)
        self.assertEqual(FakeSMTP.sent, [])

    def test_scan_only_new_and_reset_without_replay(self):
        result = self.request('scan', validity='9', cursor=2)
        self.assertEqual([m['uid'] for m in result['messages']], [3])
        self.assertEqual(self.request('scan', validity='9', cursor=3)['messages'], [])
        reset = self.request('scan', validity='old', cursor=0)
        self.assertEqual(reset['messages'], [])
        self.assertTrue(reset['reset'])

    def test_thread_reply_cannot_loop_or_redirect(self):
        self.request('reply', id='9:3', text='测试完成', prefix='[AGENT]')
        msg, envelope = FakeSMTP.sent[0]
        self.assertEqual(msg['To'], 'me@qq.com')
        self.assertEqual(msg['Subject'], 'Re: 测试')
        self.assertEqual(msg['In-Reply-To'], '<test-id@qq.com>')
        self.assertEqual(msg['Auto-Submitted'], 'auto-replied')
        self.assertFalse(bridge.should_trigger(bridge.parse_message(msg.as_bytes(), 4, '9'), 'me@qq.com', '[AGENT]'))
        self.assertEqual(envelope['to_addrs'], ['me@qq.com'])

    def test_stale_mailbox_cannot_send(self):
        with self.assertRaises(ValueError): self.request('reply', id='old:3', text='no', prefix='[AGENT]')
        self.assertFalse(FakeSMTP.sent)

if __name__ == '__main__': unittest.main()
