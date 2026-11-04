"""Fixtures de strace; no abre sockets ni inicia procesos."""
import unittest
import io
import signal
from unittest.mock import Mock, patch
from bridge_trace import Parser, TraceManager


class ParserTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.parser = Parser(10, lambda *event: self.events.append(event))

    def feed(self, call):
        self.parser.feed('10 1767225601.000000 ' + call)

    def tcp(self):
        self.feed('socket(AF_INET, SOCK_STREAM|SOCK_CLOEXEC, IPPROTO_TCP) = 3<TCP:[1]>')

    def test_no_route_is_observed_without_packet(self):
        self.tcp()
        self.feed('bind(3<TCP:[1]>, {sa_family=AF_INET, sin_port=htons(40000), sin_addr=inet_addr("0.0.0.0")}, 16) = 0')
        self.feed('connect(3<TCP:[1]>, {sa_family=AF_INET, sin_port=htons(18081), sin_addr=inet_addr("192.0.2.1")}, 16) = -1 ENETUNREACH (Network is unreachable)')
        self.assertEqual(len(self.events), 1)
        self.assertEqual(self.events[0][2], ('192.0.2.1', 18081))
        self.assertEqual(self.events[0][3], ('0.0.0.0', 40000))

    def test_unfinished_call_is_correlated(self):
        self.tcp()
        self.feed('connect(3<TCP:[1]>, {sa_family=AF_INET, sin_port=htons(27017), sin_addr=inet_addr("172.29.0.2")}, 16 <unfinished ...>')
        self.parser.feed('10 1767225602.000000 <... connect resumed>) = 0')
        self.assertEqual(len(self.events), 1)
        self.assertEqual(self.events[0][0], '1767225601.000000')

    def test_udp_payload_not_persisted(self):
        self.feed('socket(AF_INET, SOCK_DGRAM, IPPROTO_IP) = 5<UDP:[3]>')
        self.feed('sendto(5<UDP:[3]>, ""..., 100, 0, {sa_family=AF_INET, sin_port=htons(53), sin_addr=inet_addr("172.29.0.5")}, 16) = 100')
        self.assertEqual(self.events[0][1], 'UDP')
        self.assertEqual(self.events[0][2], ('172.29.0.5', 53))
        self.assertNotIn('sendto', repr(self.events))

    def test_unknown_descriptor_and_ipv6_reject(self):
        with self.assertRaises(ValueError):
            self.feed('connect(99, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.0.2.1")}, 16) = -1 EACCES (Denied)')
        with self.assertRaises(ValueError):
            self.feed('socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP) = 4')

    def test_forks_and_io_uring_reject(self):
        for call in ('fork() = 30', 'io_uring_setup(4, {}) = 7', 'clone(child_stack=NULL, flags=SIGCHLD) = 31'):
            with self.assertRaises(ValueError):
                self.feed(call)
        self.feed('clone(child_stack=0, flags=CLONE_FILES|CLONE_THREAD|CLONE_VM) = 32')

    def test_invalid_or_incomplete_trace_rejects(self):
        for line in ('truncated', 'strace: ptrace denied', '10 1767225601.000000 <... connect resumed>) = 0'):
            with self.assertRaises(ValueError):
                self.parser.feed(line)

    def test_listener_and_replies_preserve_direction(self):
        self.tcp()
        self.feed('bind(3, {sa_family=AF_INET, sin_port=htons(8080), sin_addr=inet_addr("0.0.0.0")}, 16) = 0')
        self.feed('listen(3, 128) = 0')
        self.feed('accept4(3, {sa_family=AF_INET, sin_port=htons(40001), sin_addr=inet_addr("172.29.0.8")}, [16], SOCK_CLOEXEC) = 4<TCP:[2]>')
        self.feed('sendto(4<TCP:[2]>, ""..., 2, 0, NULL, 0) = 2')
        self.assertEqual([e[4] for e in self.events], ['ACCEPT', 'REPLY'])


class CoverageTests(unittest.TestCase):
    def manager(self):
        manager = TraceManager.__new__(TraceManager)
        manager.config = {'runId': 'synthetic'}
        manager.emit = Mock()
        manager.jobs, manager.requests, manager.failure = {}, set(), None
        return manager

    def test_attach_requires_stopped_owned_target(self):
        manager = self.manager()
        with patch('builtins.open', return_value=io.BytesIO(b'unrelated\0')), patch('bridge_trace.subprocess.Popen') as process:
            with self.assertRaises(ValueError):
                manager.attach({'id': 'java', 'pid': 10, 'kind': 'java'})
            process.assert_not_called()

    def test_resume_only_after_tracer_pid_verified(self):
        manager = self.manager()
        process = Mock(pid=55)
        process.poll.return_value = None
        states = [{'State': 'T (stopped)', 'TracerPid': '0'}, {'State': 'T (stopped)', 'TracerPid': '55'}]
        with patch('builtins.open', return_value=io.BytesIO(b'/bin/sh\0bridge-trace-synthetic-java\0')), \
             patch('bridge_trace.process_status', side_effect=states), \
             patch('bridge_trace.subprocess.Popen', return_value=process), \
             patch('bridge_trace.threading.Thread'), patch('bridge_trace.signal.SIGCONT', 18, create=True), \
             patch('bridge_trace.os.kill') as kill:
            manager.attach({'id': 'java', 'pid': 10, 'kind': 'java'})
            kill.assert_called_once_with(10, signal.SIGCONT)
            self.assertTrue(manager.jobs['java']['ready'])

    def test_lost_tracer_fails_coverage(self):
        manager = self.manager()
        manager.jobs['java'] = {'ready': True, 'finishedUtc': None, 'pid': 10, 'tracerPid': 55}
        with patch('bridge_trace.process_status', side_effect=[{'State': 'R', 'TracerPid': '0'}, {'State': 'S'}]):
            with self.assertRaises(ValueError):
                manager.public()

    def test_parser_failure_fails_coverage(self):
        manager = self.manager()
        manager.failure = 'cobertura perdida'
        with self.assertRaises(ValueError):
            manager.public()

    def test_untraced_java_thread_fails_coverage(self):
        manager = self.manager()
        manager.jobs['java'] = {'ready': True, 'finishedUtc': None, 'pid': 10, 'tracerPid': 55, 'kind': 'java'}
        with patch('bridge_trace.process_status', side_effect=[{'State': 'R', 'TracerPid': '55'}, {'State': 'S'}, {'State': 'R', 'TracerPid': '0'}]), \
             patch('bridge_trace.os.listdir', return_value=['10']):
            with self.assertRaises(ValueError):
                manager.public()


if __name__ == '__main__':
    unittest.main()
