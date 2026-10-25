"""RRULE serialisation.

An RRULE whose values stayed strings serialised fine until ``to_ical()``, where
icalendar rejects a str for UNTIL. One "repeats until <date>" event therefore
returned 500 for every REPORT, GET and export of its calendar while PROPFIND
kept succeeding — which is how a Home Assistant calendar ends up discovered
under the right name and permanently unavailable.
"""

import pytest

from ical_io import _rrule_str_to_vrecur


@pytest.mark.parametrize("rule", [
    "FREQ=WEEKLY;UNTIL=20260501T235959Z",
    "FREQ=DAILY;UNTIL=20260501T235959Z;INTERVAL=2",
    "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20260501T235959Z",
])
def test_until_survives_serialisation(rule):
    """The regression: these used to raise inside to_ical()."""
    out = _rrule_str_to_vrecur(rule).to_ical().decode()
    assert "UNTIL=20260501T235959Z" in out


@pytest.mark.parametrize("rule", [
    "FREQ=WEEKLY;BYDAY=MO",
    "FREQ=DAILY;COUNT=5",
    "FREQ=WEEKLY;BYDAY=MO,WE,FR;INTERVAL=2",
    "FREQ=MONTHLY;BYMONTHDAY=15",
])
def test_rules_without_until_still_round_trip(rule):
    """These always worked; pin them so the fix did not narrow what is accepted."""
    out = _rrule_str_to_vrecur(rule).to_ical().decode()
    for part in rule.split(";"):
        key, val = part.split("=", 1)
        assert key in out
        for v in val.split(","):
            assert v in out


def test_count_and_interval_become_integers():
    """icalendar types these; the hand-rolled parser left them as strings."""
    rec = _rrule_str_to_vrecur("FREQ=DAILY;COUNT=5;INTERVAL=2")
    assert rec["COUNT"] == [5]
    assert rec["INTERVAL"] == [2]


def test_malformed_rule_raises_rather_than_corrupting():
    """build_ics catches this and drops the recurrence; it must not pass silently."""
    with pytest.raises((ValueError, TypeError)):
        _rrule_str_to_vrecur("FREQ=WEEKLY;UNTIL=not-a-date").to_ical()
