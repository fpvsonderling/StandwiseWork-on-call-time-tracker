"""Switches the app target of an Xcode project to manual signing (CI only).

  manual_signing.py PROJECT.pbxproj MARKER TEAM PROFILE_NAME IDENTITY

Every buildSettings block that contains MARKER (a line unique to the app
target, e.g. its bundle ID or entitlements file) gets manual signing with
the given team, profile and identity. Other targets are left alone.
"""
import re
import sys

path, marker, team, profile, identity = sys.argv[1:6]
text = open(path).read()
drop = re.compile(
    r'^\s*("?CODE_SIGN_IDENTITY(\[[^\]]*\])?"?|CODE_SIGN_STYLE|DEVELOPMENT_TEAM'
    r'|"?PROVISIONING_PROFILE_SPECIFIER(\[[^\]]*\])?"?|PROVISIONING_PROFILE)\s*=.*;\s*$'
)
count = 0


def patch(m: re.Match) -> str:
    global count
    body = m.group(2)
    if marker not in body:
        return m.group(0)
    count += 1
    kept = [line for line in body.split("\n") if not drop.match(line)]
    indent = "\t\t\t\t"
    added = [
        f"{indent}CODE_SIGN_STYLE = Manual;",
        f"{indent}DEVELOPMENT_TEAM = {team};",
        f'{indent}PROVISIONING_PROFILE_SPECIFIER = "{profile}";',
        f'{indent}CODE_SIGN_IDENTITY = "{identity}";',
        f'{indent}"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "{identity}";',
        f'{indent}"CODE_SIGN_IDENTITY[sdk=macosx*]" = "{identity}";',
    ]
    return m.group(1) + "\n".join(added + kept) + m.group(3)


text = re.sub(r"(buildSettings = \{\n)(.*?)(\n\t\t\t\};)", patch, text, flags=re.S)
if count == 0:
    sys.exit(f"No build configuration contains {marker!r}.")
open(path, "w").write(text)
print(f"Manual signing set in {count} build configurations.")
