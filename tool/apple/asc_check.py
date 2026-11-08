"""Prints what the App Store Connect API key can see (no secrets).

Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY (contents of the .p8 file).
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

BASE = "https://api.appstoreconnect.apple.com/v1"


def private_key() -> str:
    """The .p8 key as PEM, tolerating CRLF, lost newlines or a bare base64 body."""
    raw = os.environ["ASC_KEY"].replace("\r", "").strip()
    body = re.sub(r"-----(BEGIN|END) PRIVATE KEY-----", "", raw)
    body = re.sub(r"[^A-Za-z0-9+/=]", "", body)
    lines = [body[i : i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


def describe_key() -> None:
    raw = os.environ["ASC_KEY"]
    print(
        "Key shape: has BEGIN line:", "BEGIN PRIVATE KEY" in raw,
        "| lines:", raw.count("\n") + 1,
        "| has CR:", "\r" in raw,
        "| base64 chars:", len(re.sub(r"[^A-Za-z0-9+/=]", "", re.sub(r"-----[A-Z ]+-----", "", raw))),
    )


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        private_key(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"},
    )


def get(path: str):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:300]
        return e.code, body


def main() -> int:
    missing = [k for k in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY") if not os.environ.get(k)]
    if missing:
        print("Missing secrets:", ", ".join(missing))
        return 1
    print("Secrets present. Key ID length:", len(os.environ["ASC_KEY_ID"].strip()))
    describe_key()
    for path, show in [
        ("/apps?limit=50", lambda a: f"{a['attributes']['bundleId']} | {a['attributes']['name']}"),
        ("/bundleIds?limit=50", lambda a: f"{a['attributes']['identifier']} | {a['attributes']['platform']} | seed {a['attributes'].get('seedId')}"),
        ("/certificates?limit=50", lambda a: f"{a['attributes']['certificateType']} | {a['attributes']['name']} | expires {a['attributes'].get('expirationDate')}"),
        ("/profiles?limit=50", lambda a: f"{a['attributes']['profileType']} | {a['attributes']['name']} | {a['attributes']['profileState']}"),
    ]:
        status, data = get(path)
        print(f"\n== {path.split('?')[0]} -> HTTP {status}")
        if status == 200:
            for item in data["data"]:
                print("  ", show(item))
            if not data["data"]:
                print("   (none)")
        else:
            print("  ", data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
