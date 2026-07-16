# Publishing Calendarr on F-Droid

Two independent channels — do both in parallel:

- **Own repo (live today):** you build + sign the APK, generate a small catalog,
  host it at a URL; users add that URL in the F-Droid app.
- **Official F-Droid (~weeks to be accepted, then automatic):** F-Droid builds +
  signs from source and lists it in the catalog every F-Droid user already has.

The app is GPLv3 and has **no** non-free dependencies (no Play Services / Firebase),
so it is F-Droid-eligible. Store-listing metadata lives in `fastlane/metadata/…`.

> ⚠️ Signatures differ between the two channels: your own repo serves APKs signed
> with **your** keystore; the official build is signed with **F-Droid's** key. A
> user can't seamlessly update from one to the other (reinstall once). To unify
> later, set up *Reproducible Builds* so F-Droid ships your signature.

---

## A) Your own repo (fdroid.scarriffle.com)

The repo is just static files (APKs + a signed index). Host + generate it on an
always-on **Debian/Ubuntu LXC on Proxmox**, and keep the APK build/signing on the
Mac (where the keystore lives).

### One-time: set up the LXC

```bash
# Debian/Ubuntu LXC — fdroidserver + the Android build-tools it reads APKs with,
# plus a webserver.
apt update
apt install -y fdroidserver android-sdk-build-tools default-jdk nginx
# (if the distro has no android-sdk-build-tools pkg, install Android command-line
#  tools and `sdkmanager "build-tools;34.0.0"`, then point $ANDROID_HOME at it)

# Create the repo once (generates config.yml + an index-signing key)
mkdir -p /srv/fdroid && cd /srv/fdroid
fdroid init

# Serve /srv/fdroid via nginx/caddy at https://fdroid.scarriffle.com/fdroid
#   (document root = /srv/fdroid; TLS via your existing reverse proxy / certbot)
```

### Each release

```bash
# 1. On the MAC: build a SIGNED release APK (F-Droid repos serve APKs, not AABs)
./gradlew assembleRelease            # → app/build/outputs/apk/release/app-release.apk

# 2. Copy APK + store metadata to the LXC
scp app/build/outputs/apk/release/app-release.apk  root@lxc:/srv/fdroid/repo/
rsync -a "fastlane/metadata/android/"  root@lxc:/srv/fdroid/metadata/com.scarriffle.calendarr/

# 3. On the LXC: regenerate the signed index
cd /srv/fdroid && fdroid update -c --pretty
```

Users then open F-Droid → Settings → Repositories → **+** →
`https://fdroid.scarriffle.com/fdroid/repo` → Calendarr appears and auto-updates.

Keep the OLD apks in `repo/` too (users on older versions still update). For each
new version bump `versionCode`/`versionName` in `app/build.gradle.kts` first.

*(Fully hands-off alternative: build on the LXC too — then copy the keystore +
`keystore.properties` there and run `assembleRelease` in a checkout. The Mac
split above avoids putting the signing key on the server.)*

---

## B) Official F-Droid (fdroiddata)

Prereqs: the `SourceCode` repo in `fdroid/com.scarriffle.calendarr.yml` must be
**publicly clonable** (make the Gitea repo public, or mirror to GitHub/GitLab and
point `Repo:`/`SourceCode:` there), and a signed git tag `v1.1.0` must exist
(created for this release).

1. Fork <https://gitlab.com/fdroid/fdroiddata>.
2. Add our recipe as `metadata/com.scarriffle.calendarr.yml`
   (copy from `fdroid/com.scarriffle.calendarr.yml` in this repo).
3. Optional local sanity check: `fdroid lint com.scarriffle.calendarr` and
   `fdroid build -v -l com.scarriffle.calendarr`.
4. Open a Merge Request. F-Droid reviews, builds and publishes (this first review
   is the slow part — weeks). Afterwards, `AutoUpdateMode` picks up each new
   `v<versionName>` tag automatically.

---

## Screenshots (both channels)
Add PNG/JPG screenshots to
`fastlane/metadata/android/en-US/images/phoneScreenshots/` (and `de-DE/…`),
named `1.png`, `2.png`, … They then show on the F-Droid listing.
