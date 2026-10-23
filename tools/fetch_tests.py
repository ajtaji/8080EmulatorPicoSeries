"""Fetch the four CP/M 8080 diagnostics, pinned by commit and SHA-256.

They are not committed: CPUTEST.COM is SuperSoft's copyrighted Diagnostics II
program and the exercisers are GPL. Run this, then tools/embed_tests.py.
"""
from pathlib import Path
import hashlib, urllib.request

COMMIT = '274ffd700b81baabea99b0963bc1260b67132185'   # github.com/superzazu/8080, cpu_tests/
FILES = {
    'TST8080.COM': '9561c6fb6c99efe3de00eb77e4044fd102151058b39ac2d7bce10483838a08e7',
    'CPUTEST.COM': 'e61a9a75348c774486c2207080ea4effbf6c2367fdace31b0731081a4144030b',
    '8080PRE.COM': '18eb3c79cba42c0718f160be6a1853cb64cdce7aa47d65780189a57bdd98c4e0',
    '8080EXM.COM': '6e3286e11bb1a8f47b8ee1280b4a067be813193363e3223c99b0d21912f44aeb',
}
out = Path(__file__).resolve().parents[1] / 'Diagnostics' / 'upstream'
out.mkdir(parents=True, exist_ok=True)
for name, sha in FILES.items():
    path = out / name
    if not path.exists():
        url = f'https://raw.githubusercontent.com/superzazu/8080/{COMMIT}/cpu_tests/{name}'
        path.write_bytes(urllib.request.urlopen(url).read())
    got = hashlib.sha256(path.read_bytes()).hexdigest()
    if got != sha:
        raise SystemExit(f'{name}: SHA-256 {got}, expected {sha}')
    print(f'{name}: {path.stat().st_size} bytes, SHA-256 verified')
