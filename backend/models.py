from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Text, UniqueConstraint
from sqlalchemy.orm import relationship
from database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    # Login name: always lowercase, unique, used for authentication.
    username = Column(String(50), unique=True, nullable=False)
    # Human-facing name with original casing; editable. Falls back to username.
    display_name = Column(String(100), nullable=True)
    email = Column(String(100), unique=True, nullable=True)
    password_hash = Column(String(255), nullable=False)
    is_admin = Column(Boolean, default=False)
    avatar_filename = Column(String(255), nullable=True)
    totp_secret = Column(String(32), nullable=True)
    totp_enabled = Column(Boolean, default=False)
    # When true, the user is hidden from sharing/group picker directories
    # (/users/directory). Admin user management (/users/) still shows them.
    directory_hidden = Column(Boolean, default=False, nullable=False)

    caldav_accounts = relationship(
        "CalDAVAccount", back_populates="user", cascade="all, delete-orphan"
    )
    settings = relationship(
        "UserSettings", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    local_calendars = relationship(
        "LocalCalendar", back_populates="user", cascade="all, delete-orphan"
    )
    ical_subscriptions = relationship(
        "ICalSubscription", back_populates="user", cascade="all, delete-orphan"
    )
    google_accounts = relationship(
        "GoogleAccount", back_populates="user", cascade="all, delete-orphan"
    )
    homeassistant_accounts = relationship(
        "HomeAssistantAccount", back_populates="user", cascade="all, delete-orphan"
    )

    @property
    def display(self) -> str:
        """The name to show users: display_name if set, else the login name."""
        return self.display_name or self.username


class CalDAVAccount(Base):
    __tablename__ = "caldav_accounts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)
    url = Column(String(500), nullable=False)
    username = Column(String(100), nullable=False)
    password = Column(String(255), nullable=False)
    color = Column(String(7), default="#4285f4")
    enabled = Column(Boolean, default=True)

    user = relationship("User", back_populates="caldav_accounts")
    calendars = relationship(
        "Calendar", back_populates="account", cascade="all, delete-orphan"
    )


class Calendar(Base):
    __tablename__ = "calendars"

    id = Column(Integer, primary_key=True, index=True)
    account_id = Column(Integer, ForeignKey("caldav_accounts.id"), nullable=False)
    cal_id = Column(String(500), nullable=False)
    name = Column(String(100), nullable=False)
    color = Column(String(7), nullable=True)
    enabled = Column(Boolean, default=True)
    sidebar_hidden = Column(Boolean, default=False)
    # Whether events of this calendar generate reminders/notifications on clients.
    reminders_enabled = Column(Boolean, default=True, nullable=False)

    account = relationship("CalDAVAccount", back_populates="calendars")


class UserSettings(Base):
    __tablename__ = "user_settings"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)
    default_view = Column(String(20), default="month")
    week_start_day = Column(String(10), default="monday")
    primary_color = Column(String(7), default="#4285f4")
    accent_color = Column(String(7), default="#ea4335")
    today_color = Column(String(7), default="#4285f4")
    dim_past_events = Column(Boolean, default=False)
    text_contrast = Column(Integer, default=3)
    line_contrast = Column(Integer, default=3)
    hour_height = Column(Integer, default=60)
    language = Column(String(5), default="de")
    month_divider_color = Column(String(7), default="#7090c0")
    month_label_color = Column(String(7), default="#7090c0")
    text_color = Column(String(7), nullable=True)   # Override für --text-1 (NULL = nutze text_contrast)
    line_color = Column(String(7), nullable=True)   # Override für --border  (NULL = nutze line_contrast)
    bg_color   = Column(String(7), nullable=True)   # Override für --bg-app  (NULL = Default)
    # Surface/sidebar/topbar colour (web sidebar + top bar, iOS top bar).
    # NULL = derive from bg_color. Device-local by default (not synced).
    surface_color = Column(String(7), nullable=True)
    # How this user's private events appear to other group members:
    # 'hidden' = invisible, 'busy' = anonymous busy block (default).
    private_event_visibility = Column(String(10), default="busy")
    # The single local calendar this user shares into all their groups
    # (combined view shows only this calendar per member). NULL = share nothing.
    group_visible_calendar_id = Column(Integer, nullable=True)
    # Default reminder in minutes-before-start applied to all events client-side
    # (0 = at start time). NULL = no default reminder.
    default_reminder_minutes = Column(Integer, nullable=True)
    # Default duration (in minutes) applied to a newly created event's end time.
    default_event_duration_minutes = Column(Integer, default=60)
    # Icon key (from GROUP_ICON_KEYS) shown next to calendars this user shares with groups.
    share_calendar_icon = Column(String(16), nullable=True)
    # How many months around the visible range clients preload/cache. Device-local
    # by default (only shared when its sync flag is on).
    cache_months = Column(Integer, default=3)
    # Whether the month view uses horizontal paging (swipe) instead of a vertical
    # scroll feed. Device-local by default (only shared when its sync flag is on).
    month_view_paged = Column(Boolean, default=False)
    # Per-setting cross-device sync overrides as JSON {key: bool}. Absent keys fall
    # back to settings_router.DEFAULT_SYNC. Account-wide (one map per user); it is
    # the single authority for which settings each client sends/fetches.
    sync_flags = Column(Text, nullable=True)

    user = relationship("User", back_populates="settings")


class AppPassword(Base):
    """Per-device app-specific password for CalDAV (Basic Auth).

    Keeps MFA intact: accounts with 2FA can't use their normal password over
    CalDAV (clients can't send a TOTP code), so they authenticate with one of
    these revocable app passwords instead. Only the bcrypt hash is stored.
    """

    __tablename__ = "app_passwords"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    label = Column(String(100), nullable=False)
    password_hash = Column(String(255), nullable=False)
    created_at = Column(String(50), nullable=True)
    last_used_at = Column(String(50), nullable=True)

    user = relationship("User")


class LocalCalendar(Base):
    __tablename__ = "local_calendars"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)
    color = Column(String(7), default="#34a853")
    enabled = Column(Boolean, default=True)
    # Whether events of this calendar generate reminders/notifications on clients.
    reminders_enabled = Column(Boolean, default=True, nullable=False)
    # CalDAV publishing (opt-in): expose this calendar as a two-way CalDAV
    # collection reachable via a secret token URL. dav_ctag changes on every
    # event write so clients detect changes; rotating the token revokes access.
    caldav_published = Column(Boolean, default=False, nullable=False)
    dav_token = Column(String(64), nullable=True, unique=True)
    dav_ctag = Column(String(32), nullable=True)
    # Birthday calendar: events are all-day, yearly-recurring; the server adds the
    # age suffix ("Anna (30)") and an is_birthday flag so clients show a cake icon.
    is_birthday = Column(Boolean, default=False, nullable=False)
    # How many days before a birthday to remind (0 = on the day). NULL = no reminder.
    # Injected as an event reminder on read so the mobile schedulers fire it.
    birthday_notify_days_before = Column(Integer, nullable=True)

    user = relationship("User", back_populates="local_calendars")
    events = relationship("LocalEvent", back_populates="calendar", cascade="all, delete-orphan")


class LocalEvent(Base):
    __tablename__ = "local_events"

    id = Column(Integer, primary_key=True, index=True)
    calendar_id = Column(Integer, ForeignKey("local_calendars.id"), nullable=False)
    uid = Column(String(255), nullable=False, unique=True)
    title = Column(String(255), nullable=False)
    start = Column(String(50), nullable=False)
    end = Column(String(50), nullable=False)
    all_day = Column(Boolean, default=False)
    location = Column(String(500), nullable=True)
    description = Column(Text, nullable=True)
    color = Column(String(7), nullable=True)
    rrule = Column(Text, nullable=True)
    exdate = Column(Text, nullable=True)  # Comma-separated YYYYMMDD dates to exclude
    # Comma-separated minutes-before-start for reminders, e.g. "10,60" (0 = at start).
    reminders = Column(Text, nullable=True)
    # Creator: set server-side from the auth token on create, never from the client.
    creator_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    # For imported events without a local user (from the .ics ORGANIZER field).
    creator_name_external = Column(Text, nullable=True)
    # Private events are filtered for other group members per their visibility setting.
    is_private = Column(Boolean, default=False)
    # CalDAV entity tag — changes on every write so CalDAV clients detect updates.
    etag = Column(String(32), nullable=True)
    # Stable external identity for imported entries (e.g. a Contacts birthday keyed
    # by "contact:<id>"), so a re-sync can mirror the address book without dupes.
    external_uid = Column(String(255), nullable=True, index=True)
    # Birth year for birthday events; NULL = year unknown (no age shown).
    birth_year = Column(Integer, nullable=True)

    calendar = relationship("LocalCalendar", back_populates="events")
    creator = relationship("User")


class ICalSubscription(Base):
    __tablename__ = "ical_subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)
    url = Column(String(1000), nullable=False)
    color = Column(String(7), default="#46bdc6")
    enabled = Column(Boolean, default=True)
    # Whether events of this subscription generate reminders/notifications on clients.
    reminders_enabled = Column(Boolean, default=True, nullable=False)
    refresh_minutes = Column(Integer, default=60)
    last_fetched = Column(DateTime, nullable=True)
    cached_ics = Column(Text, nullable=True)

    user = relationship("User", back_populates="ical_subscriptions")
    overrides = relationship("ICalOverride", back_populates="subscription", cascade="all, delete-orphan")


class ICalOverride(Base):
    __tablename__ = "ical_overrides"

    id = Column(Integer, primary_key=True, index=True)
    subscription_id = Column(Integer, ForeignKey("ical_subscriptions.id"), nullable=False)
    event_uid = Column(String(500), nullable=False)
    hidden = Column(Boolean, default=False)
    title = Column(String(255), nullable=True)
    start = Column(String(50), nullable=True)
    end = Column(String(50), nullable=True)
    all_day = Column(Boolean, nullable=True)
    location = Column(String(500), nullable=True)
    description = Column(Text, nullable=True)
    color = Column(String(7), nullable=True)

    subscription = relationship("ICalSubscription", back_populates="overrides")


class GoogleAccount(Base):
    __tablename__ = "google_accounts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    email = Column(String(255), nullable=False)
    access_token = Column(Text, nullable=False)
    refresh_token = Column(Text, nullable=False)
    token_expiry = Column(DateTime, nullable=True)

    user = relationship("User", back_populates="google_accounts")
    calendars = relationship(
        "GoogleCalendar", back_populates="account", cascade="all, delete-orphan"
    )


class GoogleCalendar(Base):
    __tablename__ = "google_calendars"

    id = Column(Integer, primary_key=True, index=True)
    account_id = Column(Integer, ForeignKey("google_accounts.id"), nullable=False)
    cal_id = Column(String(500), nullable=False)
    name = Column(String(255), nullable=False)
    color = Column(String(7), nullable=True)
    enabled = Column(Boolean, default=True)
    sidebar_hidden = Column(Boolean, default=False)
    # Whether events of this calendar generate reminders/notifications on clients.
    reminders_enabled = Column(Boolean, default=True, nullable=False)

    account = relationship("GoogleAccount", back_populates="calendars")


class HomeAssistantAccount(Base):
    __tablename__ = "homeassistant_accounts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)
    url = Column(String(500), nullable=False)
    token = Column(Text, nullable=False)
    auth_method = Column(String(20), default="token")
    refresh_token = Column(Text, nullable=True)
    token_expiry = Column(DateTime, nullable=True)
    client_id = Column(String(500), nullable=True)

    user = relationship("User", back_populates="homeassistant_accounts")
    calendars = relationship(
        "HomeAssistantCalendar", back_populates="account", cascade="all, delete-orphan"
    )


class HomeAssistantCalendar(Base):
    __tablename__ = "homeassistant_calendars"

    id = Column(Integer, primary_key=True, index=True)
    account_id = Column(Integer, ForeignKey("homeassistant_accounts.id"), nullable=False)
    entity_id = Column(String(255), nullable=False)
    name = Column(String(255), nullable=False)
    color = Column(String(7), nullable=True)
    enabled = Column(Boolean, default=True)
    sidebar_hidden = Column(Boolean, default=False)
    # Whether events of this calendar generate reminders/notifications on clients.
    reminders_enabled = Column(Boolean, default=True, nullable=False)

    account = relationship("HomeAssistantAccount", back_populates="calendars")


# ── Collaboration: sharing & groups (local calendars only) ────────────────


class CalendarShare(Base):
    """A local calendar shared with another Calendarr user."""

    __tablename__ = "calendar_shares"
    __table_args__ = (
        UniqueConstraint("calendar_id", "user_id", name="uq_calendar_share"),
    )

    id = Column(Integer, primary_key=True, index=True)
    calendar_id = Column(Integer, ForeignKey("local_calendars.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    permission = Column(String(20), default="read")  # 'read' | 'read_write'
    created_at = Column(String(50), nullable=True)  # ISO 8601

    calendar = relationship("LocalCalendar")
    user = relationship("User")


class CalendarColorPref(Base):
    """A user's personal colour for a calendar they don't own — works for any
    way a foreign calendar becomes visible (direct share, group calendar, or a
    co-member's group-visible calendar). NULL/absent = the owner's colour."""

    __tablename__ = "calendar_color_prefs"
    __table_args__ = (
        UniqueConstraint("calendar_id", "user_id", name="uq_calendar_color_pref"),
    )

    id = Column(Integer, primary_key=True, index=True)
    calendar_id = Column(Integer, ForeignKey("local_calendars.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    color = Column(String(16), nullable=False)


class Group(Base):
    __tablename__ = "groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    icon = Column(String(16), nullable=True)  # emoji shown for the group
    created_by = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(String(50), nullable=True)  # ISO 8601

    members = relationship(
        "GroupMember", back_populates="group", cascade="all, delete-orphan"
    )
    group_calendar = relationship(
        "GroupCalendar", back_populates="group", uselist=False,
        cascade="all, delete-orphan",
    )


class GroupMember(Base):
    __tablename__ = "group_members"
    __table_args__ = (
        UniqueConstraint("group_id", "user_id", name="uq_group_member"),
    )

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("groups.id"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    role = Column(String(10), default="member")  # 'owner' | 'member'
    color = Column(String(7), nullable=True)  # this member's colour within the group
    joined_at = Column(String(50), nullable=True)  # ISO 8601

    group = relationship("Group", back_populates="members")
    user = relationship("User")


class BirthdaySyncDevice(Base):
    """A device that has synced Contacts birthdays into the user's birthday
    calendar. Powers the web "birthdays come from these devices" list. One row
    per (user, device); the client sends a stable device_id + human name."""

    __tablename__ = "birthday_sync_devices"
    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_birthday_sync_device"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    device_id = Column(String(64), nullable=False)
    device_name = Column(String(120), nullable=False)
    last_sync = Column(String(50), nullable=True)  # ISO 8601
    count = Column(Integer, default=0)

    user = relationship("User")


class GroupCalendar(Base):
    """1:1 link between a group and its shared local calendar."""

    __tablename__ = "group_calendars"
    __table_args__ = (
        UniqueConstraint("group_id", name="uq_group_calendar_group"),
        UniqueConstraint("calendar_id", name="uq_group_calendar_calendar"),
    )

    id = Column(Integer, primary_key=True, index=True)
    group_id = Column(Integer, ForeignKey("groups.id"), nullable=False)
    calendar_id = Column(Integer, ForeignKey("local_calendars.id"), nullable=False)

    group = relationship("Group", back_populates="group_calendar")
    calendar = relationship("LocalCalendar")
