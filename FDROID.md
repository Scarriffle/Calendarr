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

Needs the `fdroidserver` tool + Android SDK build-tools (for `aapt`).

```bash
# 1. Install the tool (macOS)
brew install fdroidserver          # or: pipx install fdroidserver

# 2. Build a SIGNED release APK (uses keystore.properties; F-Droid repos serve
#    APKs, not AABs)
./gradlew assembleRelease
# → app/build/outputs/apk/release/app-release.apk

# 3. Create the repo (once). Generates config.yml + an index-signing key.
mkdir -p ~/calendarr-fdroid && cd ~/calendarr-fdroid
fdroid init

# 4. Drop the signed APK in and copy the store metadata
cp "/path/to/Calendarr Android/app/build/outputs/apk/release/app-release.apk" repo/
mkdir -p metadata
# copy the fastlane texts/icons so descriptions show in the client:
cp -r "/path/to/Calendarr Android/fastlane/metadata/android" metadata/com.scarriffle.calendarr

# 5. Generate/refresh the signed index
fdroid update -c --pretty

# 6. Upload the whole ~/calendarr-fdroid/repo directory to your webserver at:
#    https://fdroid.scarriffle.com/fdroid/repo
```

Users then open F-Droid → Settings → Repositories → **+** →
`https://fdroid.scarriffle.com/fdroid/repo` → Calendarr appears and auto-updates.

**Each new release:** bump `versionCode`/`versionName` in `app/build.gradle.kts`,
`./gradlew assembleRelease`, copy the new APK into `repo/`, `fdroid update -c`,
re-upload. Keep the OLD apks in `repo/` too (users on older versions still update).

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
