#!/usr/bin/env python3
"""Grant Accessibility access to an app on a disposable CI Mac by writing the system TCC database.

Usage: sudo python3 grant-accessibility.py <path to .app>
Only for CI runners, where System Integrity Protection is off. Never run this on your own Mac.
"""
import plistlib
import sqlite3
import sys
import time

app = sys.argv[1].rstrip("/")
with open(f"{app}/Contents/Info.plist", "rb") as handle:
    info = plistlib.load(handle)
executable = f"{app}/Contents/MacOS/{info['CFBundleExecutable']}"
bundle_id = info["CFBundleIdentifier"]

database = sqlite3.connect("/Library/Application Support/com.apple.TCC/TCC.db")
columns = database.execute("PRAGMA table_info(access)").fetchall()
print("access columns:", ", ".join(column[1] for column in columns))

now = int(time.time())
for client, client_type in ((executable, 1), (bundle_id, 0)):
    known = {
        "service": "kTCCServiceAccessibility", "client": client, "client_type": client_type,
        "auth_value": 2, "auth_reason": 4, "auth_version": 1, "flags": 0,
        "indirect_object_identifier": "UNUSED", "last_modified": now,
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
    print("granted", client)
database.commit()
