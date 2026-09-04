# SPDX-License-Identifier: AGPL-3.0-or-later
"""E.64 — завантаження UA-набору «Перелік заходів з поліпшення санітарного стану лісів».

Джерело: data.gov.ua (Держлісагентство, CC BY 4.0). Межі придатності набору —
`docs/05_05_Slashing_and_Risk_Policy.md` §8.5; тут лише транспорт.

    python3 tools/ground_truth/fetch.py            # у tools/ground_truth/raw/
    python3 tools/ground_truth/fetch.py --out DIR

🔴 `User-Agent` НЕСУЧИЙ, не косметика. Без браузерного UA портал віддає
Cloudflare-челендж, який попередній прохід прочитав як «HTTP 429 rate-limit» і
згаяв 52 хв на backoff. Лік — форма запиту, не затримка: ⛔ НЕ додавати сюди
ретраї «щоб надійніше» — усі ресурси тягнуться послідовно за один прохід.

Список ресурсів НЕ хардкодиться: він береться з CKAN `package_show`, тож
перейменування чи новий квартал приїжджають самі. Кожен файл записується в
manifest.json разом із SHA-256 — це і провенанс, і вхід для дедуплікації
байтових дублів у `build_slice.py` (портал уже одного разу опублікував
2024-Q3 як побайтову копію 2024-Q1).
"""

import argparse
import hashlib
import json
import pathlib
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

DATASET_ID = "8ce0f975-8962-410f-a905-d90539e2f014"
API = "https://data.gov.ua/api/3/action/package_show?id=" + DATASET_ID

# Браузерний UA — див. шапку модуля. Значення довільне, важлива лише форма.
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

TIMEOUT_S = 300


def _ssl_context() -> ssl.SSLContext:
    """CA-набір для TLS — СИСТЕМНИЙ, а не `certifi`.

    🔴 Виміряно на робочій станції власника 2026-09-04, і підстава не та, на яку
    схоже: зʼєднання термінує **Zscaler** (корпоративна TLS-інспекція), тобто
    сертифікат `data.gov.ua` підписаний `Zscaler Intermediate Root CA`, а не
    публічним CA. Цей корінь лежить у Keychain — тому `curl` тягне URL без
    проблем, — але його НЕМАЄ в `certifi`, тож і дефолтний контекст, і явний
    `cafile=certifi.where()` падають `CERTIFICATE_VERIFY_FAILED` ще на
    `package_show`. ⚠️ Прочитати це як «портал недоступний» означало б винести
    вердикт про чужий сервіс із поведінки власного інтерпретатора — рівно та
    помилка, що вже коштувала цій нозі 52 хв під іменем «HTTP 429».

    `truststore` віддає Python системне сховище, тож ланцюг Zscaler
    валідується так само, як у `curl`. Без пакета лишається дефолт — і тоді
    помилка нижче каже, що саме ставити.
    """
    try:
        import truststore
    except ImportError:
        return ssl.create_default_context()
    return truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)


SSL_CONTEXT = _ssl_context()


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT_S, context=SSL_CONTEXT) as resp:
        return resp.read()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=str(pathlib.Path(__file__).parent / "raw"),
                    help="тека для сирих файлів (за замовчуванням tools/ground_truth/raw)")
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print(f"CKAN package_show → {DATASET_ID}")
    try:
        pkg = json.loads(_get(API).decode("utf-8"))
    except urllib.error.URLError as err:
        if isinstance(err.reason, ssl.SSLCertVerificationError):
            print("TLS-ланцюг не верифікується — найімовірніше корпоративна інспекція (Zscaler):\n"
                  "  pip install truststore   # віддає Python системний Keychain\n"
                  f"деталі: {err.reason}", file=sys.stderr)
            return 2
        raise
    if not pkg.get("success"):
        print("CKAN відповів success=false", file=sys.stderr)
        return 1

    resources = pkg["result"].get("resources", [])
    print(f"  ресурсів у наборі: {len(resources)}")

    manifest = []
    for res in resources:
        url = res.get("url") or ""
        name = pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name
        if not name:
            print(f"  ⚠️  ресурс без імені файлу, пропущено: {res.get('id')}", file=sys.stderr)
            continue
        blob = _get(url)
        (out / name).write_bytes(blob)
        digest = hashlib.sha256(blob).hexdigest()
        manifest.append({
            "resource_id": res.get("id"),
            "name": name,
            "url": url,
            "bytes": len(blob),
            "sha256": digest,
            "last_modified": res.get("last_modified") or res.get("created"),
        })
        print(f"  ✅ {name:<28} {len(blob):>10,} B  {digest[:16]}…")

    (out / "manifest.json").write_text(
        json.dumps({"dataset_id": DATASET_ID, "resources": manifest},
                   ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nmanifest.json: {len(manifest)} ресурсів → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
