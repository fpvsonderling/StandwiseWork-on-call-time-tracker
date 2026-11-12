"""App Store Connect helper for CI (no secrets are printed).

Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY (contents of the .p8 file).

  asc.py check
  asc.py ensure-bundle --id com.example.app --name Example
  asc.py signing --bundle com.example.app --platform IOS|MAC_OS --out DIR
  asc.py require-app --bundle com.example.app
  asc.py write-key --dir DIR      (AuthKey_<id>.p8 for xcrun altool)
  asc.py wait-build --bundle com.example.app --platform IOS|MAC_OS --build N
  asc.py revoke --out DIR
  asc.py devid-setup --bundle com.example.app --repo OWNER/NAME [--force]

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


def call(method: str, path: str, body=None, attempts: int = 4):
    """One API call. Apple's API sometimes answers 5xx; GETs and DELETEs are retried."""
    data = json.dumps(body).encode() if body is not None else None
    retry = method in ("GET", "DELETE")
    for attempt in range(1, attempts + 1):
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
            status, text = e.code, e.read().decode()[:600]
        except urllib.error.URLError as e:
            status, text = 599, str(e.reason)
        if not retry or status < 500 or attempt == attempts:
            return status, text
        print(f"{method} {path.split('?')[0]}: HTTP {status}, retrying ({attempt}/{attempts - 1})", flush=True)
        time.sleep(15 * attempt)


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


DEVID_SECRETS = ("MACOS_DEVID_P12", "MACOS_DEVID_PASSWORD", "MACOS_DEVID_PROFILE")
DEVID_PROFILE_NAME = "Standwise Direct (Developer ID)"


def github(method: str, path: str, body=None):
    """GitHub REST call with GH_SECRETS_TOKEN (fine-grained token, Secrets: write)."""
    req = urllib.request.Request(
        "https://api.github.com" + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={
            "Authorization": "Bearer " + os.environ["GH_SECRETS_TOKEN"].strip(),
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def put_secret(repo: str, name: str, value: str) -> None:
    from nacl import encoding, public

    status, key = github("GET", f"/repos/{repo}/actions/secrets/public-key")
    if status >= 300:
        raise RuntimeError(f"Read the repository public key: HTTP {status} {key}")
    box = public.SealedBox(public.PublicKey(key["key"].encode(), encoding.Base64Encoder()))
    sealed = base64.b64encode(box.encrypt(value.encode())).decode()
    status, data = github(
        "PUT", f"/repos/{repo}/actions/secrets/{name}", {"encrypted_value": sealed, "key_id": key["key_id"]}
    )
    if status >= 300:
        raise RuntimeError(f"Save secret {name}: HTTP {status} {data}")
    print(f"Saved secret {name}.")


def cmd_devid_setup(args):
    """Create the permanent Developer ID certificate and profile; store them as repo secrets.

    Unlike the TestFlight certificates these are never revoked: a revoked
    Developer ID certificate stops downloaded copies of the app from opening.
    """
    if not os.environ.get("GH_SECRETS_TOKEN", "").strip():
        sys.exit("Missing GH_SECRETS_TOKEN: add the SECRETS_TOKEN repository secret (docs/SETUP.md §12).")
    status, _ = github("GET", f"/repos/{args.repo}/actions/secrets/{DEVID_SECRETS[0]}")
    if status == 200 and not args.force:
        print("The Developer ID secrets already exist; nothing to do (run with force to replace them).")
        return
    if status not in (200, 404):
        sys.exit(f"Cannot read repository secrets with SECRETS_TOKEN: HTTP {status}. Check the token's permissions.")
    bundle = find_bundle(args.bundle)
    if not bundle:
        sys.exit(f"Bundle ID {args.bundle} is not registered.")
    out = args.out
    os.makedirs(out, exist_ok=True)
    password = secrets.token_urlsafe(24)
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::add-mask::{password}")
    created = []
    try:
        cert_id = None
        for cert_type in ("DEVELOPER_ID_APPLICATION_G2", "DEVELOPER_ID_APPLICATION"):
            try:
                cert_id, name = new_certificate(cert_type, out, "developer-id", password)
                created.append(("certificates", cert_id))
                break
            except SystemExit as e:
                print(e, flush=True)
        if not cert_id:
            sys.exit(
                "Apple refused to create a Developer ID certificate with this API key. Only the "
                "Account Holder may create one; see docs/SETUP.md §12 for the manual way."
            )
        status, data = call(
            "POST",
            "/profiles",
            {
                "data": {
                    "type": "profiles",
                    "attributes": {"name": DEVID_PROFILE_NAME, "profileType": "MAC_APP_DIRECT"},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                        "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
                    },
                }
            },
        )
        profile = ok(status, data, "Create Developer ID profile")["data"]
        created.append(("profiles", profile["id"]))
        p12 = base64.b64encode(open(os.path.join(out, "developer-id.p12"), "rb").read()).decode()
        put_secret(args.repo, "MACOS_DEVID_P12", p12)
        put_secret(args.repo, "MACOS_DEVID_PASSWORD", password)
        put_secret(args.repo, "MACOS_DEVID_PROFILE", profile["attributes"]["profileContent"])
        print(f"Developer ID certificate {name} and profile '{DEVID_PROFILE_NAME}' are stored as secrets.")
    except (Exception, SystemExit):
        # Do not leave a certificate behind that nothing can use.
        for kind, rid in reversed(created):
            print(f"Cleanup: delete {kind} {rid}: HTTP {call('DELETE', f'/{kind}/{rid}')[0]}")
        raise
    finally:
        for f in os.listdir(out):
            os.remove(os.path.join(out, f))


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
    d = sub.add_parser("devid-setup")
    d.add_argument("--bundle", required=True)
    d.add_argument("--repo", required=True)
    d.add_argument("--out", default=os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "devid"))
    d.add_argument("--force", action="store_true")
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
        "devid-setup": cmd_devid_setup,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
