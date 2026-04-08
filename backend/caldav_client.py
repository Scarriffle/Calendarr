import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Dict, List, Optional

import caldav
from icalendar import Calendar, Event

logger = logging.getLogger(__name__)

PALETTE = ["#4285f4", "#ea4335", "#fbbc04", "#34a853", "#ff6d00", "#46bdc6", "#8e24aa"]


def _client(url: str, username: str, password: str) -> caldav.DAVClient:
    return caldav.DAVClient(url=url, username=username, password=password)


def fetch_calendars(url: str, username: str, password: str) -> List[Dict]:
    """Return list of {url, name, color} dicts for all calendars in the account."""
    try:
        client = _client(url, username, password)
        principal = client.principal()
        calendars = principal.calendars()
    except Exception as e:
        raise ValueError(f"Cannot connect to CalDAV server: {e}") from e

    result = []
    for idx, cal in enumerate(calendars):
        try:
            try:
                name = cal.get_properties([caldav.elements.dav.DisplayName()])[
                    "{DAV:}displayname"
                ]
            except Exception:
                name = str(cal.url).rstrip("/").split("/")[-1] or "Calendar"

            color = None
            try:
                props = cal.get_properties(
                    [caldav.elements.cdav.CalendarColor()]
                )
                raw = props.get("{http://apple.com/ns/ical/}calendar-color", "")
                if raw and len(raw) >= 7:
                    color = raw[:7]
            except Exception:
                pass

            result.append(
                {
                    "url": str(cal.url),
                    "name": name or "Calendar",
                    "color": color or PALETTE[idx % len(PALETTE)],
                }
            )
        except Exception as exc:
            logger.warning("Could not inspect calendar %s: %s", cal.url, exc)
            result.append(
                {
                    "url": str(cal.url),
                    "name": "Calendar",
                    "color": PALETTE[idx % len(PALETTE)],
                }
            )
    return result


def fetch_events(
    url: str,
    username: str,
    password: str,
    calendar_url: str,
    start: datetime,
    end: datetime,
) -> List[Dict]:
    """Fetch events from a calendar within [start, end]."""
    try:
        client = _client(url, username, password)
        cal = client.calendar(url=calendar_url)
        resources = cal.date_search(start=start, end=end, expand=True)
    except Exception as exc:
        logger.error("Error fetching events from %s: %s", calendar_url, exc)
        return []

    events = []
    for resource in resources:
        try:
            parsed = _parse_ics(resource.data, str(resource.url))
            if parsed:
                events.extend(parsed)
        except Exception as exc:
            logger.warning("Could not parse event %s: %s", resource.url, exc)
    return events


def _parse_ics(raw: str, event_url: str) -> List[Dict]:
    """Parse raw ICS data and return a list of event dicts."""
    cal = Calendar.from_ical(raw)
    results = []
    for component in cal.walk():
        if component.name != "VEVENT":
            continue
        try:
            uid = str(component.get("UID", uuid.uuid4()))
            title = str(component.get("SUMMARY", "Untitled"))
            location = str(component.get("LOCATION", "") or "")
            description = str(component.get("DESCRIPTION", "") or "")
            color = str(component.get("X-CALENDARR-COLOR", "") or "")

            dtstart_prop = component.get("DTSTART")
            dtend_prop = component.get("DTEND")
            duration_prop = component.get("DURATION")

            if dtstart_prop is None:
                continue

            dtstart = dtstart_prop.dt
            all_day = isinstance(dtstart, date) and not isinstance(dtstart, datetime)

            if all_day:
                if dtend_prop:
                    dtend = dtend_prop.dt
                elif duration_prop:
                    dtend = dtstart + duration_prop.dt
                else:
                    dtend = dtstart + timedelta(days=1)
                start_str = dtstart.isoformat()
                end_str = dtend.isoformat() if isinstance(dtend, date) else dtstart.isoformat()
            else:
                if dtstart.tzinfo is None:
                    dtstart = dtstart.replace(tzinfo=timezone.utc)
                if dtend_prop:
                    dtend = dtend_prop.dt
                    if isinstance(dtend, date) and not isinstance(dtend, datetime):
                        dtend = datetime.combine(dtend, datetime.min.time()).replace(
                            tzinfo=timezone.utc
                        )
                    elif dtend.tzinfo is None:
                        dtend = dtend.replace(tzinfo=timezone.utc)
                elif duration_prop:
                    dtend = dtstart + duration_prop.dt
                else:
                    dtend = dtstart + timedelta(hours=1)
                start_str = dtstart.isoformat()
                end_str = dtend.isoformat()

            results.append(
                {
                    "id": uid,
                    "url": event_url,
                    "title": title,
                    "start": start_str,
                    "end": end_str,
                    "allDay": all_day,
                    "location": location,
                    "description": description,
                    "color": color or None,
                }
            )
        except Exception as exc:
            logger.warning("Skipping malformed VEVENT: %s", exc)
    return results


def create_event(
    url: str,
    username: str,
    password: str,
    calendar_url: str,
    data: Dict,
) -> str:
    client = _client(url, username, password)
    cal_obj = client.calendar(url=calendar_url)

    cal = Calendar()
    cal.add("prodid", "-//Calendarr//EN")
    cal.add("version", "2.0")

    event = Event()
    uid = str(uuid.uuid4())
    event.add("uid", uid)
    event.add("summary", data.get("title", "New Event"))
    event.add("dtstamp", datetime.now(timezone.utc))

    if data.get("allDay"):
        start = date.fromisoformat(data["start"][:10])
        end_raw = data.get("end", data["start"])[:10]
        end = date.fromisoformat(end_raw)
        if end <= start:
            end = start + timedelta(days=1)
        event.add("dtstart", start)
        event.add("dtend", end)
    else:
        start = _parse_dt(data["start"])
        end = _parse_dt(data["end"])
        event.add("dtstart", start)
        event.add("dtend", end)

    if data.get("location"):
        event.add("location", data["location"])
    if data.get("description"):
        event.add("description", data["description"])
    if data.get("color"):
        event.add("x-calendarr-color", data["color"])

    cal.add_component(event)
    cal_obj.save_event(cal.to_ical().decode("utf-8"))
    return uid


def update_event(
    url: str, username: str, password: str, event_url: str, data: Dict
):
    client = _client(url, username, password)
    resource = caldav.Event(client=client, url=event_url)
    resource.load()
    raw = resource.data

    cal = Calendar.from_ical(raw)
    new_cal = Calendar()
    for key, val in cal.items():
        new_cal.add(key, val)

    for component in cal.walk():
        if component.name != "VEVENT":
            if component.name != "VCALENDAR":
                new_cal.add_component(component)
            continue

        if "title" in data or "summary" in data:
            component["SUMMARY"] = data.get("title", data.get("summary", ""))

        if "start" in data:
            if data.get("allDay"):
                component["DTSTART"] = date.fromisoformat(data["start"][:10])
            else:
                component["DTSTART"] = _parse_dt(data["start"])

        if "end" in data:
            if data.get("allDay"):
                component["DTEND"] = date.fromisoformat(data["end"][:10])
            else:
                component["DTEND"] = _parse_dt(data["end"])

        if "location" in data:
            component["LOCATION"] = data["location"]
        if "description" in data:
            component["DESCRIPTION"] = data["description"]
        if "color" in data:
            component["X-CALENDARR-COLOR"] = data["color"]

        new_cal.add_component(component)

    resource.data = new_cal.to_ical().decode("utf-8")
    resource.save()


def delete_event(url: str, username: str, password: str, event_url: str):
    client = _client(url, username, password)
    resource = caldav.Event(client=client, url=event_url)
    resource.delete()


def _parse_dt(s: str) -> datetime:
    s = s.replace("Z", "+00:00")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt
