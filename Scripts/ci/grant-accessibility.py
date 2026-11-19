#!/usr/bin/env python3
"""Manage Accessibility access for an app on a disposable CI Mac by editing the system TCC database.

Only for CI runners, where System Integrity Protection is off. Never run this on your own Mac.

  sudo python3 grant-accessibility.py <app>                    allow this path and bundle ID (any signature)
  sudo python3 grant-accessibility.py --requirement-of <app>   allow the bundle ID only for code that meets
                                                               this build's designated requirement, as
                                                               System Settings does
  sudo python3 grant-accessibility.py --remove <app>           remove every entry for the app
"""
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import time

mode = "any"
arguments = sys.argv[1:]
if arguments[0] in ("--requirement-of", "--remove"):
    mode = arguments.pop(0)
app = arguments[0].rstrip("/")

with open(f"{app}/Contents/Info.plist", "rb") as handle:
    info = plistlib.load(handle)
executable = f"{app}/Contents/MacOS/{info['CFBundleExecutable']}"
bundle_id = info["CFBundleIdentifier"]

database = sqlite3.connect("/Library/Application Support/com.apple.TCC/TCC.db")
columns = database.execute("PRAGMA table_info(access)").fetchall()


def remove():
    database.execute(
        "DELETE FROM access WHERE service = 'kTCCServiceAccessibility' AND client IN (?, ?)",
        (bundle_id, executable),
    )


def insert(client, client_type, requirement):
    known = {
        "service": "kTCCServiceAccessibility", "client": client, "client_type": client_type,
        "auth_value": 2, "auth_reason": 4, "auth_version": 1, "flags": 0, "csreq": requirement,
        "indirect_object_identifier": "UNUSED", "last_modified": int(time.time()),
    }
    names, values = [], []
    for _, name, kind, not_null, default, _ in columns:
        if name in known:
            names.append(name)
            values.append(known[name])
        elif not_null and default is None:
            names.append(name)
            values.append(0 if "INT" in (kind or "").upper() else "UNUSED")
    placeholders = ", ".join("?" for _ in names)
    database.execute(f"INSERT OR REPLACE INTO access ({', '.join(names)}) VALUES ({placeholders})", values)


def designated_requirement_blob(path):
    shown = subprocess.run(["codesign", "--display", "--requirements", "-", path],
                           capture_output=True, text=True, check=True)
    text = (shown.stdout + shown.stderr)
    line = next(l for l in text.splitlines() if l.startswith("designated => "))
    requirement = line[len("designated => "):]
    print("designated requirement:", requirement)
    with tempfile.NamedTemporaryFile(suffix=".csreq") as blob:
        subprocess.run(["csreq", "-r", "=" + requirement, "-b", blob.name], check=True)
        return open(blob.name, "rb").read()


remove()
if mode == "any":
    insert(executable, 1, None)
    insert(bundle_id, 0, None)
    print("allowed", executable, "and", bundle_id, "for any signature")
elif mode == "--requirement-of":
    insert(bundle_id, 0, designated_requirement_blob(app))
    print("allowed", bundle_id, "for code meeting the designated requirement of", app)
else:
    print("removed Accessibility entries for", bundle_id)
database.commit()
