# Remembrance

A small macOS app for running the audio at a Canadian Remembrance Day service: **O Canada**, **the
Last Post**, **two minutes of silence**, **the Rouse** and **God Save the King**, using the official
Government of Canada recordings.

![Remembrance window](docs/screenshot.png)

## Running the service

- **Space** plays the selected cue. Space does nothing while a cue is sounding, so a double press
  can't restart anything.
- **Esc** fades out over 1.5 s; **Shift-Esc** stops at once. **↑/↓** move the selection.
- When the Last Post ends, **the two-minute silence starts by itself** and counts down. Then the
  Rouse is selected and waits for you. If no piper plays a Lament, tick "Sound the Rouse when the
  silence ends" to play it automatically.
- **Last Post timing:** the header shows when the Last Post must start so its last note sounds at
  11:00 (10:58:36 with the official recording). Tick "Start it automatically" and the app starts
  it on the second. "Silence at" changes the target time for services that aren't at 11:00.
- The header shows the Mac's **sound output** (check it says your PA/speaker, not "MacBook Pro
  Speakers"). The Mac won't sleep or dim while the app is open, and it asks before quitting
  mid-cue.
- To use a different recording for any cue (say, a live bugler's recording), right-click its row →
  **Use a Different Recording…**.

Recordings are timed by where the sound dies away, not the end of the file. The official Last Post
has about 7 seconds of quiet room tail; ignoring it keeps the silence starting on time.

See **[docs/ORDER-OF-SERVICE.md](docs/ORDER-OF-SERVICE.md)** for the researched order of service,
timings and sources.

## Install

Download the DMG from [Releases](https://github.com/rdougan/remembrance/releases) and drag
Remembrance to Applications. Releases are signed with Developer ID and notarized.

## Build

Needs only the Xcode Command Line Tools (macOS 14+):

```sh
scripts/build-app.sh      # downloads the recordings, builds build/Remembrance.app (ad-hoc signed)
open build/Remembrance.app
```

Every push to `main` that changes the app builds, signs, notarizes and publishes a release
(`.github/workflows/release.yml`, the same signing steps as the finances app). One-time setup on
the Mac with the certificate:

```sh
scripts/set-release-secrets.sh <DeveloperID.p12> <AuthKey_XXXXXXXXXX.p8> <issuer-id>
```

## Recordings

Not stored in this repo; `scripts/fetch-audio.sh` downloads them from canada.ca at build time.

- O Canada and God Save the King (instrumentals): Canadian Heritage. God Save the King is public
  domain.
- Last Post and Rouse: Canadian Armed Forces, *Music for commemorative ceremonies*. Crown
  copyright, provided for public use.
