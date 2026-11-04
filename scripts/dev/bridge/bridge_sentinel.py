"""Centinela independiente sin datos ni credenciales productivas."""
import datetime
import http.server
import json
import os
import sys

records = []
destination = sys.argv[1]


def persist():
    with open(destination + '.new', 'w', encoding='utf-8') as stream:
        json.dump(dict(ready=True, records=records), stream)
    os.replace(destination + '.new', destination)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if not self.path.startswith('/probe/') or len(self.path) > 160:
            self.send_error(404)
            return
        records.append(dict(timestampUtc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                            address=self.client_address[0], port=self.client_address[1],
                            correlationId=self.path[len('/probe/'):]))
        persist()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'fixture-ready')

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 18081), Handler)
    persist()
    server.serve_forever()
