#!/usr/bin/env python3
"""Calendar events for the shell's month calendar (owner's request, 11 November 2026), read from
Evolution Data Server, where GNOME Calendar keeps them. Read-only: nothing is ever written.

  events.py FROM TO      dates as YYYY-MM-DD, TO exclusive

prints one JSON line:

  {"calendars": [{"uid", "name", "color"}],
   "events": [{"calendar", "title", "location", "start", "end", "allDay"}]}

start and end are local times in ms since the epoch; an all-day event's end is the day after its
last day. Repeating events come as one entry per occurrence. Every enabled calendar is read; one
that can't be opened (an offline account) is left out rather than failing the rest.
"""

import json
import sys
from datetime import date, datetime, timedelta

import gi

gi.require_version("EDataServer", "1.2")
gi.require_version("ECal", "2.0")
gi.require_version("ICalGLib", "4.0")
from gi.repository import ECal, EDataServer, ICalGLib  # noqa: E402

TIMEOUT = 1  # a local calendar never reports itself connected: waiting longer only delays (checked)


def ms(t: ICalGLib.Time) -> tuple[int, bool]:
    """A component time as ms since the epoch, and whether it's a whole day. A time is read in its own
    zone (libical's as_timet_with_zone takes the zone the time is in, not one to convert to: passing
    UTC put a 14:30 Warsaw event at 15:30, checked); a floating time or a date is local."""
    if t.is_date():
        d = datetime(t.get_year(), t.get_month(), t.get_day())
        return int(d.timestamp() * 1000), True
    zone = t.get_timezone()
    if zone is None and not t.is_utc():
        d = datetime(t.get_year(), t.get_month(), t.get_day(), t.get_hour(), t.get_minute(), t.get_second())
        return int(d.timestamp() * 1000), False
    return int(t.as_timet_with_zone(zone) * 1000), False


def read(start: date, end: date) -> dict:
    registry = EDataServer.SourceRegistry.new_sync(None)
    begin = int(datetime.combine(start, datetime.min.time()).timestamp())
    finish = int(datetime.combine(end, datetime.min.time()).timestamp())
    calendars, events = [], []
    for source in registry.list_enabled(EDataServer.SOURCE_EXTENSION_CALENDAR):
        ext = source.get_extension(EDataServer.SOURCE_EXTENSION_CALENDAR)
        uid = source.get_uid()
        try:
            client = ECal.Client.connect_sync(source, ECal.ClientSourceType.EVENTS, TIMEOUT, None)
        except Exception as e:  # an account that's offline or gone
            print(f"events: {source.get_display_name()}: {e}", file=sys.stderr)
            continue
        calendars.append({"uid": uid, "name": source.get_display_name(), "color": ext.get_color() or ""})

        def found(comp, s, e, *_):
            first, all_day = ms(s)
            last, _ = ms(e) if e and not e.is_null_time() else (first, all_day)
            events.append({
                "calendar": uid,
                "title": comp.get_summary() or "",
                "location": comp.get_location() or "",
                "start": first,
                "end": max(last, first),
                "allDay": all_day,
            })
            return True

        try:
            client.generate_instances_sync(begin, finish, None, found)
        except Exception as e:
            print(f"events: {source.get_display_name()}: {e}", file=sys.stderr)
    events.sort(key=lambda e: (e["start"], not e["allDay"], e["title"].lower()))
    return {"calendars": calendars, "events": events}


def main() -> None:
    try:
        start = date.fromisoformat(sys.argv[1])
        end = date.fromisoformat(sys.argv[2])
    except (IndexError, ValueError):
        start = date.today().replace(day=1) - timedelta(days=7)
        end = start + timedelta(days=50)
    print(json.dumps(read(start, end)))


if __name__ == "__main__":
    main()
