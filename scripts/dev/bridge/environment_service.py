"""Servicios exclusivos del ensayo: JWKS publico y DNS sin reenvio."""
import http.server
import json
import socketserver
import struct
import sys
import threading

with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)

if config["role"] == "JWKS":
    class PublicKeys(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ("/jwks", "/health"):
                self.send_error(404)
                return
            body = json.dumps(config["jwks"] if self.path == "/jwks" else {"ready": True}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    http.server.ThreadingHTTPServer(("0.0.0.0", 8081), PublicKeys).serve_forever()
elif config["role"] == "DNS":
    def answer(data):
        if len(data) < 12 or struct.unpack_from("!H", data, 4)[0] != 1:
            raise ValueError("consulta DNS invalida")
        cursor, labels = 12, []
        while cursor < len(data) and data[cursor]:
            length = data[cursor]
            if length > 63 or cursor + 1 + length >= len(data):
                raise ValueError("nombre DNS invalido")
            labels.append(data[cursor+1:cursor+1+length].decode("ascii").lower())
            cursor += length + 1
        end = cursor + 5
        if end > len(data):
            raise ValueError("pregunta DNS truncada")
        kind, family = struct.unpack_from("!HH", data, cursor + 1)
        address = config["hosts"].get(".".join(labels))
        valid = address is not None and kind == 1 and family == 1
        flags = 0x8400 if valid else 0x8403  # autoritativo; nunca reenvia
        header = data[:2] + struct.pack("!HHHHH", flags, 1, int(valid), 0, 0)
        response = header + data[12:end]
        if valid:
            response += b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 30, 4)
            response += bytes(int(part) for part in address.split("."))
        return response

    class Datagram(socketserver.BaseRequestHandler):
        def handle(self):
            try:
                data, channel = self.request
                channel.sendto(answer(data), self.client_address)
            except (ValueError, UnicodeError):
                pass

    class Stream(socketserver.BaseRequestHandler):
        def handle(self):
            try:
                self.request.settimeout(2)
                prefix = self.request.recv(2)
                if len(prefix) != 2:
                    return
                length = struct.unpack("!H", prefix)[0]
                if length > 4096:
                    return
                data = b""
                while len(data) < length:
                    block = self.request.recv(length-len(data))
                    if not block:
                        return
                    data += block
                result = answer(data)
                self.request.sendall(struct.pack("!H", len(result)) + result)
            except (ValueError, UnicodeError, OSError):
                pass

    udp = socketserver.ThreadingUDPServer(("0.0.0.0", 53), Datagram)
    threading.Thread(target=udp.serve_forever, daemon=True).start()
    socketserver.ThreadingTCPServer(("0.0.0.0", 53), Stream).serve_forever()
else:
    raise ValueError("rol de servicio invalido")
