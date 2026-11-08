"""Prints what the App Store Connect API key can see (no secrets).

Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY (contents of the .p8 file).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT

BASE = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
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
    print("Secrets present. Key ID length:", len(os.environ["ASC_KEY_ID"]))
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
