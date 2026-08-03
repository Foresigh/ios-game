# Signal Runner — iOS 12 SpriteKit game, built entirely in the cloud (no Mac)

A tiny, dependency-free SpriteKit game (tap to jump over obstacles) built to
run on old A7/A8 iPads stuck on iOS 12.5.7 (iPad Air 1st gen, iPad mini 2/3).
No image assets, no shaders, no particle emitters — every visual is a plain
`SKShapeNode`, so it stays light on old GPUs and memory.

**You said you don't have a Mac.** That normally blocks the whole pipeline —
Xcode (needed to create the `.xcodeproj`, compile, and sign) only runs on
macOS. This project is set up specifically to avoid needing one, ever:

- The Xcode project isn't a file you create by hand or in Xcode — it's
  **generated from `project.yml`** by a tool called XcodeGen, and that
  generation step runs *inside* the Codemagic cloud build, not on your
  machine. You never open Xcode.
- Codemagic (codemagic.io) does the actual compiling, signing, and
  exporting on their own cloud Mac. Free tier covers this comfortably for a
  small project like this.
- Signing certificates/profiles are created automatically by Codemagic
  using an **App Store Connect API key** — that key is generated entirely
  on a website (appstoreconnect.apple.com), so no Keychain Access, no
  OpenSSL, no Mac for that either.
- I can't run any of this myself to pre-verify it (I have no macOS/Xcode
  access, and Codemagic needs your actual Apple Developer account) — so
  treat the first build or two as a debugging loop: if it fails, paste me
  the build log and I'll fix `project.yml` / `Info.plist` / the Swift code.

## What's in this folder

```
project.yml                XcodeGen spec — generates the Xcode project in CI
Info.plist                 hand-written, minimal, no storyboard references
Sources/GameScene.swift          the whole game
Sources/GameViewController.swift builds its own SKView in code, no storyboard
Sources/AppDelegate.swift        builds the window in code, no storyboard
codemagic.yaml              the cloud build pipeline definition
manifest.plist              OTA install manifest (placeholders) — this is how the built .ipa gets onto the iPad
web/install.html            GitHub Pages page with the Install button
ExportOptions.plist          not used by the primary flow below; kept for reference if you ever do get Mac/Xcode access
```

## The full checklist

### 1. Get a UDID for each iPad (from Windows, no Mac needed)

Ad Hoc distribution requires every target device's UDID registered with
Apple *before* the profile is created.

1. Install iTunes for Windows (or Apple Devices app if you're on Windows 11
   with the Microsoft Store version).
2. Plug the iPad in via USB, trust the computer on the iPad.
3. In iTunes, click the device, go to the summary page — click on the
   **Serial Number** line, it cycles through Serial Number → UDID → ICCID.
   Copy the UDID.

### 2. Put the project in a Git repository

- Create a GitHub repo (or GitLab/Bitbucket).
- Add all the files in this folder to it. You don't need to run `git`
  locally if you don't want to — GitHub's web UI lets you drag-and-drop
  upload files directly in the browser, since nothing here needs to be
  compiled on your machine.
- Fill in the one placeholder in `project.yml`: `com.REPLACE_ME` → your own
  reverse-DNS style identifier, e.g. `com.yourname.signalrunner` (used
  twice in that file — `bundleIdPrefix` and `PRODUCT_BUNDLE_IDENTIFIER`).

### 3. Apple Developer portal (all web-based)

1. **Certificates, Identifiers & Profiles → Identifiers** → register an App
   ID matching the bundle id you chose above.
2. **Devices** → register each iPad's UDID from step 1.
3. **App Store Connect → Users and Access → Integrations → App Store
   Connect API** → generate a new key with **Developer** (or Admin) access.
   Note the **Key ID** and **Issuer ID**, and download the `.p8` file —
   Apple only lets you download it once, so keep it safe.

### 4. Codemagic setup

1. Sign up at codemagic.io (free tier), connect your Git provider, add this
   repo as an app.
2. **Team settings → Integrations → Apple Developer Portal** → paste in the
   Issuer ID, Key ID, and upload the `.p8` file from step 3. This is what
   lets Codemagic automatically create and manage your Ad Hoc certificate
   and provisioning profile — no manual profile-wrangling anywhere.
3. In `codemagic.yaml`, update:
   - `BUNDLE_ID` → same bundle id as `project.yml`
   - the email under `publishing` → your own address, so Codemagic notifies
     you when a build finishes
4. Codemagic reads `codemagic.yaml` automatically from the repo root — no
   separate dashboard config needed for the build steps themselves.

### 5. Trigger a build

- Push a commit (even a trivial one) to the `main` branch, or use
  Codemagic's dashboard "Start new build" button.
- Watch the build log. **This is the first real compile of this code —**
  I could not test it myself. If a step fails, copy the error from the log
  and send it to me; most likely culprits are a typo'd bundle id, a
  `project.yml` key XcodeGen doesn't recognize, or a Swift compile error,
  all fixable from here without needing your own Mac.
- On success, the workflow produces a `.ipa` artifact and emails you.

### 6. Get the `.ipa` onto the iPad (OTA install, no cable, no Mac)

1. Download the `.ipa` artifact from the finished Codemagic build page.
2. Upload it as a **GitHub Release asset** in your repo (Releases → Draft a
   new release → attach the `.ipa`) — this gives it a stable, direct https
   download link.
3. Fill in `manifest.plist`'s placeholders:
   - `url` → the https link to the `.ipa` release asset
   - `bundle-identifier` → must exactly match what's in `project.yml`
   - `bundle-version` → `1.0` (matches `MARKETING_VERSION` in `project.yml`)
   - `title` → whatever you want shown on the install prompt
4. Push `manifest.plist` and `web/install.html` to the repo, enable
   **GitHub Pages** (repo Settings → Pages → deploy from a branch) — this
   serves https automatically, which `itms-services://` requires.
5. Edit `install.html`'s `itms-services://` link so its `url=` parameter
   points at the https URL of your hosted `manifest.plist`.

### 7. Install on the iPad

- Open **Safari** (must be Safari, not another app's browser) on the iPad,
  go to your GitHub Pages `install.html` URL, tap **Install**.
- First launch will be blocked as **"Untrusted Developer"** — go to
  **Settings → General → VPN & Device Management**, tap the developer
  profile, tap **Trust**. Then launch the app.

## Updating the game later

Edit the Swift files → push to the repo → Codemagic rebuilds and re-signs
automatically → download the new `.ipa` → replace the GitHub Release asset
→ bump `bundle-version` in `manifest.plist` if you want iOS to recognize it
as an update. No Xcode, no Mac, at any point in this loop.

## Notes / gotchas

- Ad Hoc profiles expire (about a year) — Codemagic's automatic signing
  will need to regenerate them; you may need to re-run a build.
- Adding a new iPad later: register its UDID (step 1), no other changes —
  Codemagic's automatic signing picks up newly registered devices on the
  next build.
- This never touches the App Store — no App Store Connect Testflight/review
  steps anywhere in this flow, only the API key for automated signing.
- If you ever do get occasional access to a Mac, you don't have to change
  anything here — `project.yml` also works locally with
  `xcodegen generate` followed by opening the resulting `.xcodeproj` in
  Xcode normally.
