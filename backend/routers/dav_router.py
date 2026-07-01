"""Minimal two-way CalDAV server for published local calendars.

Each published local calendar is reachable as a CalDAV collection at
``/dav/{token}/`` (secret token = auth). Supports the subset real clients
(Thunderbird, DAVx5, Apple Calendar) need: OPTIONS, PROPFIND, REPORT
(calendar-query / calendar-multiget), GET, PUT and DELETE. Change detection is
ctag-based (CS:getctag on the collection + getetag per event), which avoids
maintaining deletion tombstones.

Reuses ``ical_io.build_ics`` / ``parse_ics`` for (de)serialisation. Note:
VALARM/reminders are not round-tripped (parse_ics ignores them).
"""

from __future__ import annotations

import uuid
import xml.etree.ElementTree as ET
from urllib.parse import quote, unquote
from xml.sax.saxutils import escape as xml_escape

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response
from sqlalchemy.orm import Session

import dav_util
import ical_io
import models
from database import get_db

router = APIRouter()

# XML namespaces used across WebDAV / CalDAV.
NS_DAV = "DAV:"
NS_CAL = "urn:ietf:params:xml:ns:caldav"
NS_CS = "http://calendarserver.org/ns/"
NS_ICAL = "http://apple.com/ns/ical/"

_NS_DECL = (
    'xmlns:D="DAV:" '
    'xmlns:C="urn:ietf:params:xml:ns:caldav" '
    'xmlns:CS="http://calendarserver.org/ns/" '
    'xmlns:ICAL="http://apple.com/ns/ical/"'
)

_ALLOW = "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, REPORT"
_MULTISTATUS_CT = "application/xml; charset=utf-8"


# ── Helpers ───────────────────────────────────────────────

def _resolve(token: str, db: Session) -> models.LocalCalendar | None:
    if not token:
        return None
    return (
        db.query(models.LocalCalendar)
        .filter(
            models.LocalCalendar.dav_token == token,
            models.LocalCalendar.caldav_published == True,  # noqa: E712
        )
        .first()
    )


def _events(cal: models.LocalCalendar, db: Session) -> list[models.LocalEvent]:
    return (
        db.query(models.LocalEvent)
        .filter(models.LocalEvent.calendar_id == cal.id)
        .all()
    )


def _etag(ev: models.LocalEvent) -> str:
    return ev.etag or "0"


def _resource_name(ev: models.LocalEvent) -> str:
    return f"{quote(ev.uid, safe='')}.ics"


def _collection_href(token: str) -> str:
    return f"/dav/{token}/"


def _event_href(token: str, ev: models.LocalEvent) -> str:
    return f"/dav/{token}/{_resource_name(ev)}"


def _name_cache(cal: models.LocalCalendar, db: Session) -> dict:
    owner = db.query(models.User).filter(models.User.id == cal.user_id).first()
    if owner:
        return {owner.id: (owner.display_name or owner.username)}
    return {}


def _build_ics(cal: models.LocalCalendar, evs: list[models.LocalEvent], db: Session) -> str:
    return ical_io.build_ics(cal, evs, name_cache=_name_cache(cal, db))


# ── XML builders ──────────────────────────────────────────

def _collection_propstat(cal: models.LocalCalendar, token: str) -> str:
    href = _collection_href(token)
    return f"""  <D:response>
    <D:href>{href}</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype><D:collection/><C:calendar/></D:resourcetype>
        <D:displayname>{xml_escape(cal.name or "")}</D:displayname>
        <CS:getctag>{xml_escape(cal.dav_ctag or "0")}</CS:getctag>
        <D:supported-report-set>
          <D:supported-report><D:report><C:calendar-query/></D:report></D:supported-report>
          <D:supported-report><D:report><C:calendar-multiget/></D:report></D:supported-report>
        </D:supported-report-set>
        <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>
        <ICAL:calendar-color>{xml_escape(cal.color or "#34a853")}</ICAL:calendar-color>
        <D:current-user-principal><D:href>{href}</D:href></D:current-user-principal>
        <D:principal-URL><D:href>{href}</D:href></D:principal-URL>
        <C:calendar-home-set><D:href>{href}</D:href></C:calendar-home-set>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>"""


def _event_propstat(token: str, ev: models.LocalEvent, *, with_data: bool = False,
                    ics: str | None = None) -> str:
    href = _event_href(token, ev)
    data = ""
    if with_data and ics is not None:
        data = f"\n        <C:calendar-data>{xml_escape(ics)}</C:calendar-data>"
    return f"""  <D:response>
    <D:href>{href}</D:href>
    <D:propstat>
      <D:prop>
        <D:resourcetype/>
        <D:getetag>"{xml_escape(_etag(ev))}"</D:getetag>
        <D:getcontenttype>text/calendar; charset=utf-8; component=VEVENT</D:getcontenttype>{data}
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>"""


def _multistatus(body: str) -> Response:
    xml = f'<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus {_NS_DECL}>\n{body}\n</D:multistatus>'
    return Response(content=xml, status_code=207, media_type=_MULTISTATUS_CT)


# ── Method handlers ───────────────────────────────────────

def _handle_options() -> Response:
    return Response(status_code=200, headers={
        "DAV": "1, 2, 3, calendar-access",
        "Allow": _ALLOW,
    })


def _handle_propfind(cal: models.LocalCalendar, token: str, resource: str,
                     depth: str, db: Session) -> Response:
    # PROPFIND on a single event resource.
    if resource:
        ev = _find_event(cal, resource, db)
        if not ev:
            return Response(status_code=404)
        return _multistatus(_event_propstat(token, ev))

    # Collection: always include collection props; Depth:1 adds each event.
    parts = [_collection_propstat(cal, token)]
    if depth != "0":
        for ev in _events(cal, db):
            parts.append(_event_propstat(token, ev))
    return _multistatus("\n".join(parts))


def _handle_report(cal: models.LocalCalendar, token: str, body: bytes, db: Session) -> Response:
    report_type = None
    hrefs: list[str] = []
    if body:
        try:
            root = ET.fromstring(body)
            report_type = root.tag.split("}")[-1]  # calendar-query | calendar-multiget
            hrefs = [el.text for el in root.iter(f"{{{NS_DAV}}}href") if el.text]
        except ET.ParseError:
            pass

    if report_type == "calendar-multiget" and hrefs:
        # Decode each requested href to a bare "{uid}.ics" for encoding-safe match.
        wanted = {unquote(h.rstrip("/").rsplit("/", 1)[-1]) for h in hrefs}
        evs = [ev for ev in _events(cal, db) if f"{ev.uid}.ics" in wanted]
    else:
        # calendar-query (or unknown) → return the whole calendar.
        evs = _events(cal, db)

    parts = []
    for ev in evs:
        ics = _build_ics(cal, [ev], db)
        parts.append(_event_propstat(token, ev, with_data=True, ics=ics))
    return _multistatus("\n".join(parts) if parts else "")


def _find_event(cal: models.LocalCalendar, resource: str, db: Session) -> models.LocalEvent | None:
    name = resource.rsplit("/", 1)[-1]
    if name.endswith(".ics"):
        name = name[:-4]
    uid = unquote(name)
    return (
        db.query(models.LocalEvent)
        .filter(
            models.LocalEvent.calendar_id == cal.id,
            models.LocalEvent.uid == uid,
        )
        .first()
    )


def _handle_get(cal: models.LocalCalendar, resource: str, db: Session,
                *, head: bool = False) -> Response:
    ev = _find_event(cal, resource, db)
    if not ev:
        return Response(status_code=404)
    ics = _build_ics(cal, [ev], db)
    headers = {"ETag": f'"{_etag(ev)}"'}
    return Response(
        content=b"" if head else ics,
        media_type="text/calendar; charset=utf-8",
        headers=headers,
    )


def _handle_put(cal: models.LocalCalendar, resource: str, body: bytes, db: Session) -> Response:
    try:
        parsed = ical_io.parse_ics(body)
    except ValueError:
        return Response(status_code=400)
    items = parsed.get("events") or []
    if not items:
        return Response(status_code=400)
    item = items[0]

    # Key by the VEVENT UID; fall back to the resource name.
    uid = item.get("uid")
    if not uid:
        name = resource.rsplit("/", 1)[-1]
        uid = unquote(name[:-4] if name.endswith(".ics") else name) or str(uuid.uuid4())

    ev = (
        db.query(models.LocalEvent)
        .filter(models.LocalEvent.uid == uid)
        .first()
    )
    created = ev is None
    if created:
        ev = models.LocalEvent(calendar_id=cal.id, uid=uid, creator_id=cal.user_id)
        db.add(ev)
    ev.title = item.get("title") or "(ohne Titel)"
    ev.start = item["start"]
    ev.end = item["end"]
    ev.all_day = item.get("all_day", False)
    ev.location = item.get("location")
    ev.description = item.get("description")
    ev.rrule = item.get("rrule")
    ev.exdate = item.get("exdate")
    dav_util.bump_dav(cal, ev)
    db.commit()
    db.refresh(ev)
    return Response(status_code=201 if created else 204, headers={"ETag": f'"{_etag(ev)}"'})


def _handle_delete(cal: models.LocalCalendar, resource: str, db: Session) -> Response:
    ev = _find_event(cal, resource, db)
    if not ev:
        return Response(status_code=404)
    dav_util.bump_dav(cal)
    db.delete(ev)
    db.commit()
    return Response(status_code=204)


# ── Dispatch ──────────────────────────────────────────────

async def _dispatch(request: Request, token: str, resource: str, db: Session) -> Response:
    method = request.method.upper()

    # OPTIONS advertises capabilities without needing a valid token.
    if method == "OPTIONS":
        return _handle_options()

    cal = _resolve(token, db)
    if not cal:
        return Response(status_code=404)

    if method == "PROPFIND":
        depth = request.headers.get("Depth", "0")
        return _handle_propfind(cal, token, resource, depth, db)
    if method == "REPORT":
        return _handle_report(cal, token, await request.body(), db)
    if method in ("GET", "HEAD"):
        if not resource:
            # A bare collection GET: hand back the whole calendar as one .ics.
            ics = _build_ics(cal, _events(cal, db), db)
            return Response(content=ics, media_type="text/calendar; charset=utf-8")
        return _handle_get(cal, resource, db, head=(method == "HEAD"))
    if method == "PUT":
        return _handle_put(cal, resource, await request.body(), db)
    if method == "DELETE":
        if not resource:
            return Response(status_code=403)  # don't delete the collection itself
        return _handle_delete(cal, resource, db)
    return Response(status_code=405, headers={"Allow": _ALLOW})


_METHODS = ["OPTIONS", "GET", "HEAD", "PUT", "DELETE", "PROPFIND", "REPORT"]


@router.api_route("/dav/{token}", methods=_METHODS, include_in_schema=False)
async def dav_collection(token: str, request: Request, db: Session = Depends(get_db)):
    return await _dispatch(request, token, "", db)


@router.api_route("/dav/{token}/{resource:path}", methods=_METHODS, include_in_schema=False)
async def dav_resource(token: str, resource: str, request: Request, db: Session = Depends(get_db)):
    return await _dispatch(request, token, resource, db)
