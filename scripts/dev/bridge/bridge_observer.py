"""Captura AF_PACKET de metadatos. No acredita bloqueo por si sola.

Se ejecuta en el namespace de la aplicacion antes de Java. El controlador exige
prueba independiente del centinela, latidos y cero perdidas. Ningun payload se
escribe. Configuracion/control/estado son archivos privados del contenedor.
"""
import datetime
import ipaddress
import json
import os
import signal
import selectors
import socket
import struct
import sys
import time
import threading
from bridge_trace import TraceManager, utc


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def endpoint(packet):
    if len(packet) < 14:
        raise ValueError('trama truncada')
    ether = struct.unpack_from('!H', packet, 12)[0]
    if ether == 0x0806:
        return None
    if ether != 0x0800 or len(packet) < 34 or packet[14] >> 4 != 4:
        raise ValueError('protocolo de enlace/IP no admitido')
    header = (packet[14] & 15) * 4
    if header < 20 or struct.unpack_from('!H', packet, 20)[0] & 0x3fff:
        raise ValueError('cabecera fragmentada o invalida')
    protocol = packet[23]
    offset = 14 + header
    if protocol not in (6, 17) or len(packet) < offset + (20 if protocol == 6 else 8):
        raise ValueError('transporte no admitido o truncado')
    source, destination = socket.inet_ntoa(packet[26:30]), socket.inet_ntoa(packet[30:34])
    source_port, port = struct.unpack_from('!HH', packet, offset)
    flags = packet[offset + 13] if protocol == 6 else 0
    return source, destination, source_port, port, ('TCP' if protocol == 6 else 'UDP'), flags


def main(config_path, control_path, state_path):
    with open(config_path, encoding='utf-8-sig') as stream:
        config = json.load(stream)
    run_id = config['runId']
    if not isinstance(run_id, str) or not run_id:
        raise ValueError('runId invalido')
    allowed = {}
    for item in config['allowed']:
        key = (str(ipaddress.IPv4Address(item['sourceAddress'])), str(ipaddress.IPv4Address(item['address'])), item['protocol'], item['port'])
        if item['protocol'] not in ('TCP', 'UDP') or type(item['port']) is not int or not 1 <= item['port'] <= 65535 or key in allowed:
            raise ValueError('allowlist invalida')
        allowed[key] = item
    if not allowed:
        raise ValueError('allowlist vacia')
    sentinel = config['sentinel']
    sentinel_key = (sentinel['sourceAddress'], str(ipaddress.IPv4Address(sentinel['address'])), 'TCP', sentinel['port'])
    if sentinel_key in allowed or type(sentinel['sourcePort']) is not int or not 1024 <= sentinel['sourcePort'] <= 65535:
        raise ValueError('centinela invalido o autorizado')
    state = dict(runId=run_id, status='STARTING', startedUtc=now(), finishedUtc=None,
                 phase='AUTOCOMPROBACION', phaseStartedUtc=None, heartbeatUtc=now(), droppedEvents=0, events=[])
    flows = set()
    sentinel_seen = False
    allowed_seen = False
    lock = threading.RLock()

    def syscall(request, stamp, protocol, destination, local, operation, pid):
        nonlocal sentinel_seen
        address, port = destination
        key = config['appAddress'], address, protocol, port
        with lock:
            if operation in ('ACCEPT', 'REPLY'):
                incoming = any(item['sourceAddress'] == address and item['destinationId'] == config['appId'] and
                               item['port'] == 8080 and protocol == 'TCP' for item in allowed.values())
                if not incoming or (operation == 'ACCEPT' and (not local or local[1] != 8080)):
                    raise ValueError('respuesta o aceptacion ajena')
                return
            if key in allowed:
                item, correlation = allowed[key], 'allowed-syscall'
            elif (state['phase'] == 'AUTOCOMPROBACION' and request['kind'] == 'probe' and
                  request.get('correlationId') == sentinel['correlationId'] and key == sentinel_key and
                  local and local[1] == sentinel['sourcePort'] and not sentinel_seen):
                item, correlation = sentinel, sentinel['correlationId']
                sentinel_seen = True
            else:
                state['rejectedDestination'] = dict(address=address, port=port, protocol=protocol,
                                                    phase=state['phase'], timestampUtc=utc(stamp), channel='SYSCALL')
                raise ValueError('syscall hacia destino fuera de allowlist')
            state['events'].append(dict(phase=state['phase'], timestampUtc=utc(stamp), sourceId=item['sourceId'],
                                        destinationId=item['destinationId'], address=address, protocol=protocol,
                                        port=port, correlationId=correlation, outcome='ATTEMPT',
                                        channel='SYSCALL', traceId=request['id'], pid=pid))
            if len(state['events']) > 50000:
                raise ValueError('limite de eventos alcanzado')

    traces = TraceManager(config, syscall)
    state['traceVersion'] = traces.version
    state['traceTargets'] = []

    def persist():
        state['heartbeatUtc'] = now()
        state['traceTargets'] = traces.public(check=state['status'] != 'ERROR')
        with lock, open(state_path + '.new', 'w', encoding='utf-8') as stream:
            json.dump(state, stream, separators=(',', ':'))
        os.replace(state_path + '.new', state_path)

    raw = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    raw.setblocking(False)
    selector = selectors.DefaultSelector()
    selector.register(raw, selectors.EVENT_READ)
    state['status'] = 'RUNNING'
    persist()
    last = time.monotonic()
    try:
        while True:
            for _, _ in selector.select(timeout=0.1):
                packet, _ = raw.recvfrom(65535)
                parsed = endpoint(packet)
                if parsed is None:
                    continue
                source, destination, source_port, port, protocol, flags = parsed
                flow = source, destination, source_port, port, protocol
                reverse = destination, source, port, source_port, protocol
                key = source, destination, protocol, port
                if state['phase'] == 'RECORRIDO' and (key == sentinel_key or (destination, source, protocol, source_port) == sentinel_key):
                    raise ValueError('centinela observado durante recorrido')
                # Replies are admitted only for a flow observed from its initial attempt.
                if reverse in flows:
                    continue
                if protocol == 'TCP' and (not flags & 2 or flags & 16):
                    if flow not in flows:
                        raise ValueError('flujo TCP sin intento observado')
                    continue
                if flow in flows:
                    continue  # retransmision del mismo intento, incluido el centinela
                if key in allowed:
                    item = allowed[key]
                    correlation = 'allowed'
                    allowed_seen = True
                elif state['phase'] == 'AUTOCOMPROBACION' and key == sentinel_key and source_port == sentinel['sourcePort']:
                    # El intento denegado se acredita por syscall, incluso sin
                    # paquete. No duplicar el evento si tambien aparece aqui.
                    continue
                else:
                    raise ValueError('destino fuera de allowlist')
                flows.add(flow)
                state['events'].append(dict(phase=state['phase'], timestampUtc=now(),
                    sourceId=item['sourceId'], destinationId=item['destinationId'], address=destination,
                    protocol=protocol, port=port, correlationId=correlation, outcome='ATTEMPT', channel='PACKET'))
                if len(state['events']) > 50000:
                    raise ValueError('limite de eventos alcanzado')
            if time.monotonic() - last >= 0.25:
                if os.path.exists('/opt/bridge-trace-request.json'):
                    with open('/opt/bridge-trace-request.json', encoding='utf-8-sig') as request_stream:
                        traces.attach(json.load(request_stream))
                state['traceTargets'] = traces.public()
                _, dropped = struct.unpack('II', raw.getsockopt(263, 6, 8))
                state['droppedEvents'] += dropped
                if state['droppedEvents']:
                    raise ValueError('paquetes perdidos')
                with open(control_path, encoding='utf-8-sig') as stream:
                    control = json.load(stream)
                if control == {'phase': 'RECORRIDO'} and state['phase'] == 'AUTOCOMPROBACION':
                    if not allowed_seen or not sentinel_seen:
                        raise ValueError('autocomprobacion sin intentos requeridos')
                    state['phase'] = 'RECORRIDO'
                    state['phaseStartedUtc'] = now()
                elif control == {'stop': True}:
                    if state['phase'] != 'RECORRIDO':
                        raise ValueError('cierre antes de recorrido')
                    traces.stop()
                    state['status'] = 'STOPPED'
                    state['finishedUtc'] = now()
                    persist()
                    return
                elif control not in ({'phase': 'AUTOCOMPROBACION'}, {'phase': 'RECORRIDO'}):
                    raise ValueError('control invalido')
                persist()
                last = time.monotonic()
    except Exception as failure:
        # El namespace PID es exclusivamente el de la APP. Detener su Java
        # inmediatamente; nunca se opera sobre procesos del host u otros ensayos.
        for pid in os.listdir('/proc'):
            if not pid.isdigit():
                continue
            try:
                with open('/proc/' + pid + '/cmdline', 'rb') as command:
                    parts = command.read(65536).split(b'\0')
                if b'/opt/bridge.jar' in parts and any(p.endswith(b'/java') or p == b'java' for p in parts[:1]):
                    os.kill(int(pid), signal.SIGKILL)
            except (ProcessLookupError, FileNotFoundError, PermissionError):
                pass
        state['status'] = 'ERROR'
        state['reason'] = str(failure)
        state['finishedUtc'] = now()
        persist()
        raise
    finally:
        raw.close()


if __name__ == '__main__':
    main(*sys.argv[1:])
