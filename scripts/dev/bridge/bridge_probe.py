"""Sonda TCP sintetica. Solo recibe direcciones numericas de recursos nuevos."""
import datetime
import ipaddress
import json
import socket
import sys


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main():
    address = str(ipaddress.IPv4Address(sys.argv[1]))
    port, source_port = int(sys.argv[2]), int(sys.argv[3])
    correlation = sys.argv[4]
    if not 1 <= port <= 65535 or not 0 <= source_port <= 65535:
        raise ValueError('puerto invalido')
    started = now()
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as connection:
        connection.settimeout(5)
        connection.bind(('0.0.0.0', source_port))
        error = None
        connected = False
        acknowledged = False
        try:
            connection.connect((address, port))
            connected = True
            connection.sendall(('GET /probe/' + correlation + ' HTTP/1.0\r\nHost: fixture\r\n\r\n').encode('ascii'))
            response = connection.recv(4096)
            acknowledged = b'200 OK' in response
        except OSError as failure:
            error = failure.errno
        source_address, actual_source_port = connection.getsockname()
    print(json.dumps(dict(startedUtc=started, finishedUtc=now(), connected=connected,
                         acknowledged=acknowledged, sourceAddress=source_address,
                         sourcePort=actual_source_port, address=address, port=port,
                         correlationId=correlation, errorCode=error)))


if __name__ == '__main__':
    main()
