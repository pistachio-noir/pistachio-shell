"""Calendar events (`psc events FROM TO`, rust/psc/src/events.rs; Python's events.py until 20 November 2026)
against a private Evolution Data Server: its own session bus (dbus-run-session), a temporary home and XDG
folders, GSettings in memory and TZ=Europe/Warsaw. The owner's calendars are never seen.

Seeds a weekly event in Europe/Warsaw that crosses the switch to summer time, a UTC event, a two-day all-day
event, a floating-time event, an untitled event without an end, an event outside the range, a second calendar
("Work") and a calendar whose backend doesn't exist ("Broken", standing in for an offline account), then
checks the JSON. While src/services/events.py still exists, its output must equal psc's (parity).

  python3 -B tests/events.test.py            PSC=path to test another build (default rust/target/release/psc)
"""
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
PSC = os.environ.get("PSC", str(ROOT / "rust/target/release/psc"))
OLD = ROOT / "src/services/events.py"
RANGE = ["2026-03-01", "2026-04-01"]
FLOATING = ("Floating lunch", "Review")  # no zone and no Z: local time
WARSAW = ZoneInfo("Europe/Warsaw")


def outside():
    """Set up the temporary home and run this file again inside its own session bus."""
    with tempfile.TemporaryDirectory(prefix="events-test-") as tmp:
        tmp = Path(tmp)
        env = {k: v for k, v in os.environ.items() if not k.startswith(("DBUS_", "XDG_", "GIO_", "GSETTINGS"))}
        env.update(
            HOME=str(tmp / "home"), XDG_CONFIG_HOME=str(tmp / "config"), XDG_DATA_HOME=str(tmp / "data"),
            XDG_CACHE_HOME=str(tmp / "cache"), XDG_RUNTIME_DIR=str(tmp / "run"), GSETTINGS_BACKEND="memory",
            TZ="Europe/Warsaw", PSC=PSC, EVENTS_TEST_INSIDE="1",
        )
        for d in ("home", "config", "data", "cache", "run"):
            (tmp / d).mkdir(mode=0o700)
        sources = tmp / "config/evolution/sources"
        sources.mkdir(parents=True)
        (sources / "work.source").write_text(
            "[Data Source]\nDisplayName=Work\nEnabled=true\nParent=local-stub\n\n"
            "[Calendar]\nBackendName=local\nColor=#7da3b3\nSelected=true\n")
        (sources / "broken.source").write_text(
            "[Data Source]\nDisplayName=Broken\nEnabled=true\nParent=local-stub\n\n"
            "[Calendar]\nBackendName=no-such-backend\nColor=#db8267\nSelected=true\n")
        result = subprocess.run(["dbus-run-session", "--", sys.executable, "-B", __file__], env=env, timeout=180)
        # EDS's daemons end a moment after their bus closes; any still running after 10 s are killed and fail the test
        for _ in range(20):
            left = ours(tmp)
            if not left:
                break
            time.sleep(0.5)
        if left:
            for pid in left:
                os.kill(pid, 15)
            print(f"FAIL fixture left processes running (stopped now): {sorted(left)}")
            sys.exit(1)
        sys.exit(result.returncode)


def ours(tmp: Path) -> set:
    """Processes started for this fixture: those whose environment holds its temporary home."""
    mark = f"XDG_CONFIG_HOME={tmp}/config".encode()
    found = set()
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                if mark in (entry / "environ").read_bytes().split(b"\0"):
                    found.add(int(entry.name))
            except OSError:
                pass
    return found


def ms(dt: datetime) -> int:
    return int(dt.timestamp() * 1000)


def local(*a) -> datetime:
    return datetime(*a, tzinfo=WARSAW)


def utc(*a) -> datetime:
    return datetime(*a, tzinfo=timezone.utc)


def ics(uid, lines):
    return "\r\n".join(["BEGIN:VEVENT", f"UID:{uid}", "DTSTAMP:20260101T000000Z", *lines, "END:VEVENT"])


def seed():
    import gi
    gi.require_version("EDataServer", "1.2")
    gi.require_version("ECal", "2.0")
    gi.require_version("ICalGLib", "4.0")
    from gi.repository import ECal, EDataServer, ICalGLib

    registry = EDataServer.SourceRegistry.new_sync(None)
    clients = {}
    for uid in ("system-calendar", "work"):
        source = registry.ref_source(uid)
        assert source is not None, f"the fixture has no {uid} calendar"
        clients[uid] = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, 1, None)
    clients["system-calendar"].add_timezone_sync(ICalGLib.Timezone.get_builtin_timezone("Europe/Warsaw"), None)
    events = {
        "system-calendar": [
            ics("standup", ["SUMMARY:Weekly standup", "DTSTART;TZID=Europe/Warsaw:20260302T093000",
                            "DTEND;TZID=Europe/Warsaw:20260302T094500", "RRULE:FREQ=WEEKLY;COUNT=5"]),
            ics("dentist", ["SUMMARY:Dentist", "LOCATION:Clinic", "DTSTART:20260305T143000Z", "DTEND:20260305T150000Z"]),
            ics("holiday", ["SUMMARY:Holiday", "DTSTART;VALUE=DATE:20260310", "DTEND;VALUE=DATE:20260312"]),
            ics("lunch", ["SUMMARY:Floating lunch", "DTSTART:20260311T120000", "DTEND:20260311T130000"]),
            ics("untitled", ["DTSTART:20260312T080000Z"]),
            ics("later", ["SUMMARY:Outside the range", "DTSTART:20260420T100000Z", "DTEND:20260420T110000Z"]),
        ],
        "work": [ics("review", ["SUMMARY:Review", "DTSTART:20260304T100000", "DTEND:20260304T110000"])],
    }
    for uid, comps in events.items():
        for text in comps:
            clients[uid].create_object_sync(ICalGLib.Component.new_from_string(text), ECal.OperationFlags.NONE, None)


def run(cmd):
    p = subprocess.run(cmd + RANGE, capture_output=True, text=True, timeout=60)
    return p.returncode, p.stdout, p.stderr


def inside():
    failures = []

    def check(ok, what):
        print(("ok: " if ok else "FAIL: ") + what)
        if not ok:
            failures.append(what)

    seed()
    code, out, err = run([os.environ["PSC"], "events"])
    check(code == 0, f"psc events exits 0 (got {code}; stderr: {err.strip()[:300]})")
    try:
        new = json.loads(out)
    except ValueError:
        print("FAIL: psc events printed no JSON:", out[:300])
        sys.exit(1)

    if OLD.exists():
        code, out_old, err_old = run([sys.executable, "-I", str(OLD)])
        old = json.loads(out_old)
        # floating times are the one intended difference: events.py read them as UTC (EDS's default zone)
        same = lambda d: {"calendars": d["calendars"], "events": [e for e in d["events"] if e["title"] not in FLOATING]}
        check(same(old) == same(new), "parity: psc events prints what events.py printed (floating times aside)")
        if old != new:
            print("events.py:", json.dumps(old, indent=1)[:3000])
            print("psc:", json.dumps(new, indent=1)[:3000])

    names = sorted(c["name"] for c in new["calendars"])
    check("Work" in names and "Personal" in names and "Broken" not in names, f"every calendar that opens, the broken one left out ({names})")
    check(any(c["color"].lower() == "#7da3b3" for c in new["calendars"]), "a calendar's colour comes through")
    check("Broken" in err, "the calendar that can't be opened is named on stderr")

    by = {}
    for e in new["events"]:
        by.setdefault(e["title"], []).append(e)
    standup = by.get("Weekly standup", [])
    check([e["start"] for e in standup] == [ms(local(2026, 3, d, 9, 30)) for d in (2, 9, 16, 23, 30)],
          "a weekly event comes once per week, at 09:30 Warsaw time before and after the switch to summer time")
    check(all(e["end"] - e["start"] == 15 * 60000 and not e["allDay"] for e in standup), "each occurrence lasts 15 minutes")
    dentist = by.get("Dentist", [{}])[0]
    check(dentist.get("start") == ms(utc(2026, 3, 5, 14, 30)) and dentist.get("location") == "Clinic", "a UTC event at its instant, with its location")
    holiday = by.get("Holiday", [{}])[0]
    check(holiday.get("allDay") is True and holiday.get("start") == ms(local(2026, 3, 10)) and holiday.get("end") == ms(local(2026, 3, 12)),
          "an all-day event runs from local midnight to the local midnight after its last day")
    untitled = by.get("", [{}])[0]
    check(untitled.get("start") == ms(utc(2026, 3, 12, 8)) and untitled.get("end") == untitled.get("start"), "an untitled event without an end ends where it starts")
    check("Outside the range" not in by, "an event outside the range is left out")
    review = by.get("Review", [{}])[0]
    work = next((c["uid"] for c in new["calendars"] if c["name"] == "Work"), None)
    check(review.get("calendar") == work, "an event names its calendar")
    lunch, review = by.get("Floating lunch", [{}])[0], by.get("Review", [{}])[0]
    check(lunch.get("start") == ms(local(2026, 3, 11, 12)) and lunch.get("end") == ms(local(2026, 3, 11, 13))
          and review.get("start") == ms(local(2026, 3, 4, 10)),
          "a floating time is local time (12:00 shows at 12:00, not as 12:00 UTC)")
    keys = [(e["start"], not e["allDay"], e["title"].lower()) for e in new["events"]]
    check(keys == sorted(keys), "events are sorted by start, all-day first, then title")

    print("PASS events" if not failures else f"FAIL events: {len(failures)} failed")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    inside() if os.environ.get("EVENTS_TEST_INSIDE") else outside()
