from pathlib import Path
import hashlib
import io
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from install_server_toolchain import download


class ServerToolchainTests(unittest.TestCase):
    def test_download_checksum_is_required_and_cached_download_is_rechecked(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'tool.zip'
            checksum=hashlib.sha512(b'official archive').hexdigest()
            with patch('urllib.request.urlopen',return_value=io.BytesIO(b'official archive')) as request:
                download('https://example.invalid/tool.zip',path,checksum)
                self.assertTrue(request.called)
            with patch('urllib.request.urlopen') as request:
                download('https://example.invalid/tool.zip',path,checksum)
                request.assert_not_called()
            path.write_bytes(b'changed cache')
            with patch('urllib.request.urlopen',return_value=io.BytesIO(b'untrusted replacement')):
                with self.assertRaises(ValueError):download('https://example.invalid/tool.zip',path,checksum)
            self.assertEqual(path.read_bytes(),b'changed cache')
