#!/usr/bin/env python3
# Boot entries for the power menu's "Restart into…" (services/Session.qml). Limine publishes its menu in
# the boot loader interface's EFI variables, readable without root: LoaderEntries (all of them) and
# LoaderEntrySelected (the one booted now, left out). Prints one JSON line.
import glob
import json
import re

VENDOR = "4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"


def read(name):
    found = glob.glob(f"/sys/firmware/efi/efivars/{name}-{VENDOR}")
    if not found:
        return []
    try:
        data = open(found[0], "rb").read()[4:]  # 4 bytes of attributes, then UTF-16 strings
        return [entry for entry in data.decode("utf-16-le").split("\0") if entry]
    except (OSError, UnicodeDecodeError):
        return []


def pretty(entry):
    # Limine turns non-alphanumerics into "-": "Arch Linux (linux)" arrives as "Arch-Linux--linux-"
    entry = re.sub(r"--(.+?)-$", r" (\1)", entry)
    return re.sub(r"-+", " ", entry).strip() or entry


current = (read("LoaderEntrySelected") or [""])[0]
print(json.dumps({
    "efi": bool(glob.glob("/sys/firmware/efi")),
    "entries": [{"id": entry, "name": pretty(entry)} for entry in read("LoaderEntries") if entry != current],
}))
