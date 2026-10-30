"""The interface and the proxy hold no key-shaped string, no bearer value, no Portuguese, and no address that is not the product's own.
Scans the committed text of frontend/ (not node_modules or dist), src/ops/proxy/ and the demo scenarios."""
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FOLDERS = ["frontend/src", "frontend/tests", "frontend/scripts", "src/ops/proxy"]
EXTRA = ["frontend/index.html", "frontend/package.json", "frontend/vite.config.ts", "frontend/tsconfig.json", "data/samples/demo-scenarios.json"]
TEXT = (".ts", ".tsx", ".css", ".mjs", ".json", ".html", ".sh", ".template", ".inc", "Dockerfile")


def files():
    out = []
    for folder in FOLDERS:
        for base, dirs, names in os.walk(os.path.join(ROOT, folder)):
            dirs[:] = [d for d in dirs if d not in ("node_modules", "dist", ".vite")]
            out += [os.path.join(base, n) for n in names if n.endswith(TEXT)]
    out += [os.path.join(ROOT, e) for e in EXTRA]
    return out


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def test_there_are_files_to_scan():
    assert len(files()) > 20


def test_no_key_shaped_string_and_no_bearer_value():
    for path in files():
        text = read(path)
        assert not re.search(r"sk-[A-Za-z0-9_-]{16,}", text), path
        assert not re.search(r"Bearer\s+[A-Za-z0-9._-]{12,}", text), path


def test_no_portuguese():
    words = re.compile(r"\b(não|você|crítico|ação|descrição|resultado crítico|leitura de retorno|obrigatório|usuário|senha)\b", re.IGNORECASE)
    accents = re.compile(r"[áàâãéêíóôõúç]", re.IGNORECASE)
    for path in files():
        text = read(path)
        assert not words.search(text), path
        assert not accents.search(text), path


def test_no_external_address_in_the_sources():
    allowed = ("localhost", "127.0.0.1", "www.w3.org")
    for path in files():
        if path.endswith(("package.json", ".mjs")):
            continue  # package metadata and the check scripts name hosts on purpose
        for match in re.finditer(r"https?://([A-Za-z0-9.-]+)", read(path)):
            assert match.group(1) in allowed, "%s names %s" % (path, match.group(0))
