import functools
import http.client
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

from serve_web import WebHandler


class ServeWebHandlerTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        root = Path(self.temp_dir.name)
        (root / "index.html").write_text("<!doctype html>", encoding="utf-8")
        (root / "index.js").write_text("console.log('ready');", encoding="utf-8")
        (root / "index.wasm").write_bytes(b"wasm")
        handler = functools.partial(WebHandler, directory=str(root))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp_dir.cleanup()

    def test_static_responses_keep_runtime_headers_and_mime_types(self):
        expected = {
            "/index.html": ("text/html", b"<!doctype html>"),
            "/index.js": ("text/javascript", b"console.log('ready');"),
            "/index.wasm": ("application/wasm", b"wasm"),
        }
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port)
        try:
            for path, (mime_type, body) in expected.items():
                with self.subTest(path=path):
                    connection.request("GET", path)
                    response = connection.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.getheader("Content-Type"), mime_type)
                    self.assertEqual(response.getheader("Cache-Control"), "no-cache")
                    self.assertEqual(response.getheader("Cross-Origin-Opener-Policy"), "same-origin")
                    self.assertEqual(response.getheader("Cross-Origin-Embedder-Policy"), "require-corp")
                    self.assertEqual(response.read(), body)
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
