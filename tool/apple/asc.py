"""App Store Connect helper for CI (no secrets are printed).

Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY (contents of the .p8 file).

  asc.py check
  asc.py ensure-bundle --id com.example.app --name Example
  asc.py signing --bundle com.example.app --platform IOS|MAC_OS --out DIR
  asc.py require-app --bundle com.example.app
  asc.py write-key --dir DIR      (AuthKey_<id>.p8 for xcrun altool)
  asc.py wait-build --bundle com.example.app --platform IOS|MAC_OS --build N
  asc.py revoke --out DIR

`signing` creates a fresh distribution certificate (and, for macOS, an
installer certificate) plus an App Store profile, writes them to DIR and
records their IDs; `revoke` deletes them again. Apple checks the signature
while it processes an upload, and a macOS build signed with a certificate that
is revoked before that check is rejected (ITMS-90238 CSSMERR_TP_CERT_REVOKED).
So CI runs `wait-build` after the upload and revokes only once processing has
finished. A build that has passed processing stays valid after revocation.
"""
import argparse
import base64
import datetime
import json
import os
import re
import secrets
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

BASE = "https://api.appstoreconnect.apple.com/v1"


def private_key() -> str:
    """The .p8 key as PEM, tolerating CRLF, lost newlines or a bare base64 body."""
    raw = os.environ["ASC_KEY"].replace("\r", "").strip()
    body = re.sub(r"-----(BEGIN|END) PRIVATE KEY-----", "", raw)
    body = re.sub(r"[^A-Za-z0-9+/=]", "", body)
    lines = [body[i : i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"].strip(),
            "iat": now,
            "exp": now + 600,
            "aud": "appstoreconnect-v1",
        },
        private_key(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"},
    )


def call(method: str, path: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:600]


def ok(status, data, what):
    if status >= 300:
        sys.exit(f"{what} failed: HTTP {status} {data}")
    return data


def find_bundle(identifier: str):
    status, data = call("GET", f"/bundleIds?filter[identifier]={identifier}&limit=20")
    ok(status, data, "List bundle IDs")
    for item in data["data"]:
        if item["attributes"]["identifier"] == identifier:
            return item
    return None


def cmd_check(_):
    for path, show in [
        ("/apps?limit=50", lambda a: f"{a['attributes']['bundleId']} | {a['attributes']['name']}"),
        ("/bundleIds?limit=50", lambda a: f"{a['attributes']['identifier']} | {a['attributes']['platform']} | team {a['attributes'].get('seedId')}"),
        ("/certificates?limit=50", lambda a: f"{a['attributes']['certificateType']} | {a['attributes']['name']} | expires {a['attributes'].get('expirationDate')}"),
        ("/profiles?limit=50", lambda a: f"{a['attributes']['profileType']} | {a['attributes']['name']} | {a['attributes']['profileState']}"),
    ]:
        status, data = call("GET", path)
        print(f"== {path.split('?')[0]} -> HTTP {status}")
        if status == 200:
            for item in data["data"] or []:
                print("  ", show(item))
        else:
            print("  ", data)


def cmd_ensure_bundle(args):
    found = find_bundle(args.id)
    if found:
        print(f"Bundle ID {args.id} exists (team {found['attributes'].get('seedId')}).")
        return
    status, data = call(
        "POST",
        "/bundleIds",
        {"data": {"type": "bundleIds", "attributes": {"identifier": args.id, "name": args.name, "platform": "UNIVERSAL"}}},
    )
    if status == 409 and find_bundle(args.id):
        print(f"Bundle ID {args.id} exists.")  # registered by a parallel job
        return
    ok(status, data, "Register bundle ID")
    print(f"Registered bundle ID {args.id}.")


def cmd_require_app(args):
    status, data = call("GET", f"/apps?filter[bundleId]={args.bundle}&limit=5")
    ok(status, data, "List apps")
    if not any(a["attributes"]["bundleId"] == args.bundle for a in data["data"]):
        sys.exit(
            f"No app with bundle ID {args.bundle} in App Store Connect yet. Create it once: "
            "App Store Connect -> Apps -> + -> New App (docs/SETUP.md)."
        )
    print(f"App {args.bundle} exists in App Store Connect.")


def cmd_write_key(args):
    os.makedirs(args.dir, exist_ok=True)
    path = os.path.join(args.dir, f"AuthKey_{os.environ['ASC_KEY_ID'].strip()}.p8")
    with open(path, "w") as f:
        f.write(private_key())
    os.chmod(path, 0o600)


def record(out: str, kind: str, rid: str) -> None:
    with open(os.path.join(out, "created.txt"), "a") as f:
        f.write(f"{kind} {rid}\n")


def new_certificate(cert_type: str, out: str, label: str, password: str):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Standwise CI")]))
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    status, data = call(
        "POST",
        "/certificates",
        {"data": {"type": "certificates", "attributes": {"certificateType": cert_type, "csrContent": csr_pem}}},
    )
    data = ok(status, data, f"Create {cert_type} certificate")["data"]
    record(out, "certificates", data["id"])
    der = base64.b64decode(data["attributes"]["certificateContent"])
    cert = x509.load_der_x509_certificate(der)
    p12 = pkcs12.serialize_key_and_certificates(
        label.encode(), key, cert, None, serialization.BestAvailableEncryption(password.encode())
    )
    with open(os.path.join(out, f"{label}.p12"), "wb") as f:
        f.write(p12)
    name = cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)[0].value
    print(f"Created {cert_type} certificate: {name}")
    return data["id"], name


def cmd_signing(args):
    os.makedirs(args.out, exist_ok=True)
    bundle = find_bundle(args.bundle)
    if not bundle:
        sys.exit(f"Bundle ID {args.bundle} is not registered.")
    password = secrets.token_urlsafe(18)
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::add-mask::{password}")
    env = {"P12_PASSWORD": password, "TEAM_ID": bundle["attributes"]["seedId"]}
    cert_id, env["SIGNING_IDENTITY"] = new_certificate("DISTRIBUTION", args.out, "distribution", password)
    if args.platform == "MAC_OS":
        _, env["INSTALLER_IDENTITY"] = new_certificate(
            "MAC_INSTALLER_DISTRIBUTION", args.out, "installer", password
        )
    profile_type = "IOS_APP_STORE" if args.platform == "IOS" else "MAC_APP_STORE"
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
    name = f"Standwise CI {args.platform} {stamp}"
    status, data = call(
        "POST",
        "/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": profile_type},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                    "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
                },
            }
        },
    )
    data = ok(status, data, "Create profile")["data"]
    record(args.out, "profiles", data["id"])
    ext = "mobileprovision" if args.platform == "IOS" else "provisionprofile"
    path = os.path.join(args.out, f"profile.{ext}")
    with open(path, "wb") as f:
        f.write(base64.b64decode(data["attributes"]["profileContent"]))
    env.update(PROFILE_NAME=name, PROFILE_UUID=data["attributes"]["uuid"], PROFILE_PATH=path)
    print(f"Created profile: {name}")
    gh_env = os.environ.get("GITHUB_ENV")
    if gh_env:
        with open(gh_env, "a") as f:
            for k, v in env.items():
                f.write(f"{k}={v}\n")


def cmd_revoke(args):
    path = os.path.join(args.out, "created.txt")
    if not os.path.exists(path):
        print("Nothing to revoke.")
        return
    # Profiles first, then the certificates they use.
    lines = [l.split() for l in open(path).read().splitlines() if l.strip()]
    for kind, rid in sorted(lines, key=lambda x: x[0] != "profiles"):
        status, _ = call("DELETE", f"/{kind}/{rid}")
        print(f"Delete {kind} {rid}: HTTP {status}")


def cmd_wait_build(args):
    """Wait until App Store Connect has finished processing an uploaded build."""
    status, data = call("GET", f"/apps?filter[bundleId]={args.bundle}&limit=5")
    apps = [a for a in ok(status, data, "List apps")["data"] if a["attributes"]["bundleId"] == args.bundle]
    if not apps:
        sys.exit(f"No app with bundle ID {args.bundle}.")
    path = (
        f"/builds?filter[app]={apps[0]['id']}&filter[version]={args.build}"
        f"&filter[preReleaseVersion.platform]={args.platform}&limit=5"
    )
    deadline = time.time() + args.timeout
    state = None
    while time.time() < deadline:
        status, data = call("GET", path)
        if status < 300 and data["data"]:
            state = data["data"][0]["attributes"].get("processingState")
            print(f"Build {args.build} ({args.platform}): {state}", flush=True)
            if state == "VALID":
                return
            if state in ("INVALID", "FAILED"):
                sys.exit(f"Apple rejected build {args.build}; see the email from App Store Connect.")
        else:
            print(f"Build {args.build} ({args.platform}) not listed yet (HTTP {status}).", flush=True)
        time.sleep(30)
    sys.exit(f"Build {args.build} still {state or 'not listed'} after {args.timeout}s.")


def main():
    for k in ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY"):
        if not os.environ.get(k):
            sys.exit(f"Missing {k}: add the App Store Connect secrets (docs/SETUP.md).")
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    b = sub.add_parser("ensure-bundle")
    b.add_argument("--id", required=True)
    b.add_argument("--name", required=True)
    s = sub.add_parser("signing")
    s.add_argument("--bundle", required=True)
    s.add_argument("--platform", choices=["IOS", "MAC_OS"], required=True)
    s.add_argument("--out", required=True)
    a = sub.add_parser("require-app")
    a.add_argument("--bundle", required=True)
    w = sub.add_parser("write-key")
    w.add_argument("--dir", required=True)
    wb = sub.add_parser("wait-build")
    wb.add_argument("--bundle", required=True)
    wb.add_argument("--platform", choices=["IOS", "MAC_OS"], required=True)
    wb.add_argument("--build", required=True)
    wb.add_argument("--timeout", type=int, default=2700)
    r = sub.add_parser("revoke")
    r.add_argument("--out", required=True)
    args = p.parse_args()
    {
        "check": cmd_check,
        "ensure-bundle": cmd_ensure_bundle,
        "require-app": cmd_require_app,
        "signing": cmd_signing,
        "write-key": cmd_write_key,
        "wait-build": cmd_wait_build,
        "revoke": cmd_revoke,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
