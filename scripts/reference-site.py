"""Serve the preserved website copy for local visual regression comparisons."""
from pathlib import Path
from http.server import SimpleHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit
root=Path(__file__).resolve().parents[1]/'web'
class Reference(SimpleHTTPRequestHandler):
    def translate_path(self,path):
        base=root/('legacy' if urlsplit(path).path.endswith('.html') else 'public')
        relative=urlsplit(path).path.lstrip('/') or 'index.html'
        target=(base/relative).resolve()
        return str(target if target.is_relative_to(base.resolve()) else base/'missing')
ThreadingHTTPServer(('127.0.0.1',3007),Reference).serve_forever()
