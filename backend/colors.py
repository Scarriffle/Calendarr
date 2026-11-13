"""One definition of "this is a colour", used wherever one is accepted or shown.

Colours are interpolated into `style="background:${color}"` in the web client
without escaping, so an unvalidated value is a stored-XSS vector — a group
member sets their own colour and every other member renders it. Validating at
the trust boundary fixes every render site at once, without touching any of
them.
"""

from __future__ import annotations

import re
from typing import Annotated, Optional

from pydantic import AfterValidator

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def _check_hex(v: Optional[str]) -> Optional[str]:
    if v is None or v == "":
        return v
    if not HEX_RE.match(v):
        raise ValueError("Farbe muss im Format #rrggbb angegeben werden")
    return v


#: Request-model field type: rejects anything but #rrggbb with a 422.
HexColor = Annotated[str, AfterValidator(_check_hex)]
#: Same, for optional fields.
OptHexColor = Annotated[Optional[str], AfterValidator(_check_hex)]


def safe_hex(value: Optional[str], fallback: str) -> str:
    """Clamp a colour that came from an upstream provider (Google, CalDAV, HA).

    Not user input, but not ours either, and it lands in the same markup.
    """
    return value if value and HEX_RE.match(value) else fallback
