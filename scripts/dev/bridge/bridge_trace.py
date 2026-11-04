"""strace en memoria: solo persiste destinos y cobertura; nunca lineas/payloads."""
import datetime
import ipaddress
import json
import os
import re
import signal
import subprocess
import threading
import time

CALLS = ('socket,socketpair,connect,bind,listen,accept,accept4,sendto,sendmsg,sendmmsg,'
         'close,dup,dup2,dup3,fcntl,clone,clone3,fork,vfork,execve,execveat,io_uring_setup')
PREFIX = re.compile(r'^(?:(?:\[pid\s+(\d+)\]|(\d+))\s+)?(\d+\.\d+)\s+(.*)$')
ADDRESS = re.compile(r'sa_family=AF_INET,\s*sin_port=htons\((\d+)\),\s*sin_addr=inet_addr\("([0-9.]+)"\)')


def utc(epoch):
    return datetime.datetime.fromtimestamp(float(epoch), datetime.timezone.utc).isoformat()


def process_status(pid):
    try:
        with open('/proc/%d/status' % pid, encoding='ascii') as stream:
            return dict(line.rstrip().split(':', 1) for line in stream if ':' in line)
    except FileNotFoundError:
        return None


class Parser:
    """Un proceso y sus threads CLONE_FILES; forks sin tabla compartida rechazan."""
    def __init__(self, root_pid, emit):
        self.root_pid, self.emit = root_pid, emit
        self.sockets, self.pending = {}, {}

    def feed(self, line):
        if len(line) > 65536:
            raise ValueError('linea de traza demasiado grande')
        line = line.strip()
        if not line:
            return
        if line.startswith('strace:'):
            if 'attached' in line:
                return
            raise ValueError('diagnostico inesperado del trazador')
        match = PREFIX.match(line)
        if not match:
            raise ValueError('formato de strace no reconocido')
        pid, stamp, body = int(match[1] or match[2] or self.root_pid), match[3], match[4]
        if body.startswith(('+++', '---')):
            return
        if '<unfinished ...>' in body:
            self.pending[pid] = (stamp, body.split('<unfinished ...>')[0])
            return
        if body.startswith('<... '):
            if pid not in self.pending or 'resumed>' not in body:
                raise ValueError('retorno sin entrada de syscall')
            stamp, initial = self.pending.pop(pid)
            body = initial + body.split('resumed>', 1)[1]
        call_match = re.match(r'(\w+)\((.*)\)\s+=\s+(.+)$', body)
        if not call_match:
            raise ValueError('syscall incompleta')
        call, args, result = call_match.groups()
        # Solo permitir procesos nuevos que comparten tabla de fds: threads JVM.
        if call in ('fork', 'vfork', 'io_uring_setup'):
            raise ValueError('mecanismo de proceso/red no cubierto')
        if call in ('clone', 'clone3'):
            if not result.startswith('-1') and not ('CLONE_THREAD' in args and 'CLONE_FILES' in args):
                raise ValueError('fork fuera de cobertura')
            return
        if call in ('execve', 'execveat'):
            return  # Los argumentos nunca se guardan.
        if call in ('socket', 'socketpair'):
            if result.startswith('-1'):
                return
            family = args.split(',', 1)[0]
            if family not in ('AF_INET', 'AF_UNIX', 'AF_NETLINK'):
                raise ValueError('familia de socket no cubierta')
            if family != 'AF_INET':
                return
            protocol = 'TCP' if 'SOCK_STREAM' in args else 'UDP' if 'SOCK_DGRAM' in args else None
            if not protocol:
                raise ValueError('socket IP no cubierto')
            fd_match = re.match(r'(\d+)', result)
            if not fd_match:
                raise ValueError('descriptor de socket no verificable')
            self.sockets[int(fd_match[1])] = dict(protocol=protocol, local=None, remote=None)
            return
        fd_match = re.match(r'(\d+)', args)
        if not fd_match:
            raise ValueError('descriptor no verificable')
        fd = int(fd_match[1])
        if call == 'close':
            if not result.startswith('-1'):
                self.sockets.pop(fd, None)
            return
        if call in ('dup', 'dup2', 'dup3', 'fcntl'):
            if fd in self.sockets and (call != 'fcntl' or 'F_DUPFD' in args) and not result.startswith('-1'):
                duplicate = re.match(r'(\d+)', result)
                if duplicate:
                    self.sockets[int(duplicate[1])] = dict(self.sockets[fd])
            return
        if fd not in self.sockets:
            # Locales UNIX/NETLINK, anotados por strace con -yy. No son egreso IP.
            if '<UNIX' in args or '<NETLINK' in args or 'sa_family=AF_UNIX' in args or 'sa_family=AF_NETLINK' in args:
                return
            raise ValueError('socket IP sin alta observada')
        entry = self.sockets[fd]
        addresses = [(str(ipaddress.IPv4Address(m[2])), int(m[1])) for m in ADDRESS.finditer(args)]
        if 'AF_INET6' in args:
            raise ValueError('IPv6 fuera de cobertura')
        if call == 'bind':
            if addresses and not result.startswith('-1'):
                entry['local'] = addresses[0]
            return
        if call == 'listen':
            return
        if call in ('accept', 'accept4'):
            if result.startswith('-1'):
                return
            if len(addresses) != 1 or not entry['local']:
                raise ValueError('aceptacion sin extremos verificables')
            accepted = re.match(r'(\d+)', result)
            if not accepted:
                raise ValueError('aceptacion sin descriptor')
            self.emit(stamp, entry['protocol'], addresses[0], entry['local'], 'ACCEPT', pid)
            self.sockets[int(accepted[1])] = dict(protocol=entry['protocol'], local=entry['local'], remote=addresses[0], accepted=True)
            return
        if call in ('connect', 'sendto', 'sendmsg', 'sendmmsg'):
            if not addresses:
                if not entry.get('remote'):
                    raise ValueError('envio sin destino verificable')
                addresses = [entry['remote']]
            for destination in addresses:
                self.emit(stamp, entry['protocol'], destination, entry['local'],
                          'REPLY' if entry.get('accepted') else 'ATTEMPT', pid)
            if call == 'connect':
                entry['remote'] = addresses[0]
            return
        raise ValueError('syscall no cubierta')


class TraceManager:
    def __init__(self, config, emit):
        self.config, self.emit = config, emit
        self.jobs, self.requests = {}, set()
        self.failure = None
        version = subprocess.run(['strace', '--version'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=5)
        self.version = version.stdout.decode('ascii', 'replace').splitlines()[0]
        supported = re.search(r'\bversion\s+(\d+)\.', self.version)
        if not supported or int(supported[1]) < 6:
            raise ValueError('strace 6 o posterior requerido')

    def attach(self, request):
        key, pid = request['id'], request['pid']
        if key in self.requests:
            return
        if type(pid) is not int or pid <= 1 or request['kind'] not in ('java', 'probe'):
            raise ValueError('objetivo de traza invalido')
        marker = 'bridge-trace-' + self.config['runId'] + '-' + key
        with open('/proc/%d/cmdline' % pid, 'rb') as stream:
            if marker.encode('ascii') not in stream.read(65536).split(b'\0'):
                raise ValueError('objetivo de traza ajeno')
        status = process_status(pid)
        if not status or not status['State'].strip().startswith('T'):
            raise ValueError('objetivo no detenido antes de exec')
        process = subprocess.Popen(['strace', '-f', '-qq', '-ttt', '-yy', '-s', '0', '-e', 'trace=' + CALLS, '-p', str(pid)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, bufsize=1)
        job = dict(id=key, pid=pid, tracerPid=process.pid, kind=request['kind'], ready=False, startedUtc=None,
                   finishedUtc=None, exitCode=None, threadChecks=0, lastThreadCheckUtc=None, process=process, request=dict(request))
        self.jobs[key] = job
        self.requests.add(key)
        parser = Parser(pid, lambda *args: self.emit(request, *args))

        def read():
            try:
                for line in process.stderr:
                    parser.feed(line)
                code = process.wait()
                status = process_status(pid)
                if code != 0 or (status and not status['State'].strip().startswith('Z')):
                    raise ValueError('trazador termino con objetivo vivo o error')
                if parser.pending:
                    raise ValueError('traza termino con syscalls incompletas')
                job['exitCode'] = code
                job['finishedUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            except Exception:
                self.failure = 'cobertura de syscalls perdida o no interpretable'
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        threading.Thread(target=read, daemon=True).start()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            status = process_status(pid)
            if self.failure or process.poll() is not None:
                raise ValueError('no se pudo conectar strace')
            if status and int(status['TracerPid'].strip()) == process.pid:
                job['ready'] = True
                job['startedUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                os.kill(pid, signal.SIGCONT)
                return
            time.sleep(0.02)
        raise ValueError('timeout verificando TracerPid')

    def public(self, check=True):
        if check and self.failure:
            raise ValueError(self.failure)
        if check:
            for job in self.jobs.values():
                if job['ready'] and not job['finishedUtc']:
                    check_stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    target = process_status(job['pid'])
                    tracer = process_status(job['tracerPid'])
                    if target and not target['State'].strip().startswith('Z'):
                        if (not tracer or tracer['State'].strip().startswith(('T', 'Z')) or
                                int(target['TracerPid'].strip()) != job['tracerPid']):
                            raise ValueError('trazador desconectado o detenido con objetivo activo')
                        if job['kind'] == 'java':
                            try:
                                tids = os.listdir('/proc/%d/task' % job['pid'])
                            except FileNotFoundError:
                                tids = []
                            for tid in tids:
                                thread = process_status(int(tid))
                                if thread and not thread['State'].strip().startswith('Z') and int(thread['TracerPid'].strip()) != job['tracerPid']:
                                    raise ValueError('thread JVM sin trazador')
                            if tids:
                                job['threadChecks'] += 1
                                job['lastThreadCheckUtc'] = check_stamp
        return [dict((k, v) for k, v in job.items() if k not in ('process', 'request')) for job in self.jobs.values()]

    def stop(self):
        for job in self.jobs.values():
            try:
                job['process'].wait(timeout=2)
            except subprocess.TimeoutExpired:
                raise ValueError('cierre con objetivo aun trazado')
        deadline = time.monotonic() + 2
        while any(not job['finishedUtc'] for job in self.jobs.values()) and not self.failure and time.monotonic() < deadline:
            time.sleep(0.02)
        if any(not job['finishedUtc'] for job in self.jobs.values()):
            raise ValueError('cobertura final de syscalls incompleta')
        return self.public()
