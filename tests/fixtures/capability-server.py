#!/usr/bin/env python3
import http.server
import socketserver
import sys

FINGERPRINT = b"SHOULD_NOT_LEAK_FINGERPRINT"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/.well-known/quicktui-server-capability":
            body = b'{"ok":true,"identity_fingerprint":"' + FINGERPRINT + b'"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404)

    def log_message(self, *_args):
        return


def main():
    port = int(sys.argv[1])
    with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
