#!/usr/bin/env python3
"""Serve the slideshow over localhost.

Same as `python3 -m http.server` but every response carries
`Cache-Control: no-store` so the kiosk browser never caches static
assets. Without this, CSS / font / image updates pulled via
slideshow-update.service stayed invisible until Chromium's HTTP
cache was manually cleared.
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def main(argv: list[str]) -> int:
    bind = "127.0.0.1"
    port = 8080
    directory = "."
    args = iter(argv[1:])
    for a in args:
        if a == "--bind":
            bind = next(args)
        elif a == "--directory":
            directory = next(args)
        elif a.isdigit():
            port = int(a)
        else:
            print(f"unknown arg: {a}", file=sys.stderr)
            return 2

    handler = partial(NoCacheHandler, directory=directory)
    with ThreadingHTTPServer((bind, port), handler) as httpd:
        print(f"serving {directory} on http://{bind}:{port} (no-store)")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
