"""Transporte del harness: solicitud unica, origen fijado, sin redirecciones/logs."""
import http.client
import ipaddress
import json
import sys
from urllib.parse import urlsplit


def main():
    value = json.load(sys.stdin)
    if not isinstance(value, dict) or set(value) != {"baseUri", "path", "method", "token", "body"}:
        raise ValueError("solicitud invalida")
    base = urlsplit(value["baseUri"])
    if base.scheme != "http" or base.username or base.password or base.query or base.fragment:
        raise ValueError("origen invalido")
    address = ipaddress.ip_address(base.hostname)
    if address.version != 4 or address.is_loopback or address.is_unspecified or base.port != 8080 or base.path != "/catalog":
        raise ValueError("origen ajeno al harness")
    path, method = value["path"], value["method"]
    if not isinstance(path, str) or not path.startswith("/") or path.startswith("//") or any(c in path for c in "\r\n?#"):
        raise ValueError("ruta invalida")
    if method not in ("GET", "POST", "PUT", "DELETE"):
        raise ValueError("metodo invalido")
    headers = {"Accept": "application/json"}
    token = value["token"]
    if token is not None:
        if not isinstance(token, str) or not token or any(c in token for c in "\r\n"):
            raise ValueError("identidad invalida")
        headers["Authorization"] = "Bearer " + token
    body = None
    if value["body"] is not None:
        body = json.dumps(value["body"], separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    connection = http.client.HTTPConnection(str(address), base.port, timeout=15)
    try:
        connection.request(method, base.path + path, body=body, headers=headers)
        response = connection.getresponse()
        data = response.read(1048577)
        if len(data) > 1048576:
            raise ValueError("respuesta excede limite")
        document = json.loads(data.decode("utf-8")) if data else None
        print(json.dumps({"status": response.status, "etag": response.getheader("ETag"), "body": document}, separators=(",", ":")))
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # No imprimir excepcion: URLs, cabeceras o payloads pueden tener datos.
        print('{"transportError":true}')
        sys.exit(1)
