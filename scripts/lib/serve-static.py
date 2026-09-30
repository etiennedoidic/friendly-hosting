#!/usr/bin/env python3
"""Loopback static server for Cloudflare Tunnel origins (tunnels proxy HTTP; they cannot serve a directory).

Usage: serve-static.py <port> <directory>
"""
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".json": "application/json",
        ".webmanifest": "application/manifest+json",
        ".css": "text/css",
        ".html": "text/html",
        ".svg": "image/svg+xml",
    }


def main() -> int:
    if len(sys.argv) != 3:
        sys.stderr.write("usage: serve-static.py <port> <directory>\n")
        return 2
    port = int(sys.argv[1])
    root = Path(sys.argv[2]).resolve()
    if not root.is_dir():
        sys.stderr.write("not a directory: %s\n" % root)
        return 1

    class Rooted(Handler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(root), **kwargs)

    ThreadingHTTPServer(("127.0.0.1", port), Rooted).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
