"""iCal (.ics) import/export for local calendars.

Reuses the already-installed ``icalendar`` library. The parser produces dicts
matching the LocalEvent storage shape (ISO strings, comma-separated EXDATE);
the generator emits a VCALENDAR with ORGANIZER, RRULE, etc.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone

from icalendar import Calendar, Event, vCalAddress, vRecur, vText

logger = logging.getLogger(__name__)


def _rrule_to_str(component) -> str | None:
    prop = component.get("RRULE")
    if not prop:
        return None
    return prop.to_ical().decode("utf-8")


def _exdate_to_csv(component) -> str | None:
    """Collect EXDATE values as comma-separated YYYYMMDD strings."""
    exdate = component.get("EXDATE")
    if not exdate:
        return None
    items = exdate if isinstance(exdate, list) else [exdate]
    out = []
    for ex in items:
        dts = getattr(ex, "dts", None) or []
        for d in dts:
            val = d.dt
            if isinstance(val, datetime):
                out.append(val.strftime("%Y%m%d"))
            elif isinstance(val, date):
                out.append(val.strftime("%Y%m%d"))
    return ",".join(out) if out else None


def _organizer_name(component) -> str | None:
    org = component.get("ORGANIZER")
    if not org:
        return None
    # CN parameter holds the display name; fall back to the mailto address.
    try:
        cn = org.params.get("CN")
        if cn:
            return str(cn)
    except Exception:
        pass
    raw = str(org)
    if raw.lower().startswith("mailto:"):
        return raw[7:]
    return raw or None


def parse_ics(raw: bytes) -> dict:
    """Parse .ics bytes into {"events": [dict, ...], "errors": [str, ...]}.

    Raises ValueError if the payload is not a parseable calendar at all.
    """
    try:
        cal = Calendar.from_ical(raw)
    except Exception as e:
        raise ValueError(f"Datei ist kein gültiges iCal-Format: {e}") from e

    events = []
    errors = []
    for component in cal.walk():
        if component.name != "VEVENT":
            continue
        try:
            uid = str(component.get("UID") or uuid.uuid4())
            title = str(component.get("SUMMARY", "") or "")
            location = str(component.get("LOCATION", "") or "") or None
            description = str(component.get("DESCRIPTION", "") or "") or None

            dtstart_prop = component.get("DTSTART")
            if dtstart_prop is None:
                errors.append(f"VEVENT {uid}: kein DTSTART, übersprungen")
                continue
            dtstart = dtstart_prop.dt
            dtend_prop = component.get("DTEND")
            duration_prop = component.get("DURATION")

            all_day = isinstance(dtstart, date) and not isinstance(dtstart, datetime)
            if all_day:
                if dtend_prop:
                    dtend = dtend_prop.dt
                elif duration_prop:
                    dtend = dtstart + duration_prop.dt
                else:
                    dtend = dtstart + timedelta(days=1)
                start_str = dtstart.isoformat()
                end_str = (dtend.isoformat() if isinstance(dtend, date)
                           else (dtstart + timedelta(days=1)).isoformat())
            else:
                if dtstart.tzinfo is None:
                    dtstart = dtstart.replace(tzinfo=timezone.utc)
                if dtend_prop:
                    dtend = dtend_prop.dt
                    if isinstance(dtend, date) and not isinstance(dtend, datetime):
                        dtend = datetime.combine(dtend, datetime.min.time(), tzinfo=timezone.utc)
                    elif dtend.tzinfo is None:
                        dtend = dtend.replace(tzinfo=timezone.utc)
                elif duration_prop:
                    dtend = dtstart + duration_prop.dt
                else:
                    dtend = dtstart + timedelta(hours=1)
                start_str = dtstart.isoformat()
                end_str = dtend.isoformat()

            events.append({
                "uid": uid,
                "title": title,
                "start": start_str,
                "end": end_str,
                "all_day": all_day,
                "location": location,
                "description": description,
                "rrule": _rrule_to_str(component),
                "exdate": _exdate_to_csv(component),
                "organizer": _organizer_name(component),
            })
        except Exception as exc:
            logger.warning("Skipping malformed VEVENT: %s", exc)
            errors.append(f"Fehlerhafter Eintrag übersprungen: {exc}")
    return {"events": events, "errors": errors}


def _rrule_str_to_vrecur(rrule_str: str) -> vRecur:
    params = {}
    for part in rrule_str.split(";"):
        if "=" not in part:
            continue
        key, val = part.split("=", 1)
        params[key] = val.split(",") if "," in val else val
    return vRecur(params)


def _parse_iso(s: str) -> datetime:
    s = s.replace("Z", "+00:00")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def build_ics(calendar, events, *, name_cache: dict | None = None) -> str:
    """Build a VCALENDAR string for a local calendar and its events."""
    cal = Calendar()
    cal.add("prodid", "-//Calendarr//EN")
    cal.add("version", "2.0")
    cal.add("x-wr-calname", calendar.name)

    for ev in events:
        item = Event()
        item.add("uid", ev.uid)
        item.add("summary", ev.title or "")
        item.add("dtstamp", datetime.now(timezone.utc))

        if ev.all_day:
            try:
                start = date.fromisoformat(ev.start[:10])
                end = date.fromisoformat(ev.end[:10])
            except ValueError:
                continue
            if end <= start:
                end = start + timedelta(days=1)
            item.add("dtstart", start)
            item.add("dtend", end)
        else:
            try:
                item.add("dtstart", _parse_iso(ev.start))
                item.add("dtend", _parse_iso(ev.end))
            except ValueError:
                continue

        if ev.location:
            item.add("location", ev.location)
        if ev.description:
            item.add("description", ev.description)
        if ev.color:
            item.add("x-calendarr-color", ev.color)
        if ev.rrule:
            item.add("rrule", _rrule_str_to_vrecur(ev.rrule))

        # ORGANIZER from the creator (local user or imported name).
        organizer_name = None
        if getattr(ev, "creator_id", None) and name_cache:
            organizer_name = name_cache.get(ev.creator_id)
        if not organizer_name:
            organizer_name = getattr(ev, "creator_name_external", None)
        if organizer_name:
            organizer = vCalAddress("mailto:noreply@calendarr.local")
            organizer.params["CN"] = vText(organizer_name.replace('"', ""))
            item.add("organizer", organizer)

        cal.add_component(item)

    return cal.to_ical().decode("utf-8")
