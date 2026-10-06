# MeN Go ticket integration (0.1.125)

## Backup

Before editing, saved the repository bundle, tracked-source ZIP and installed
0.1.124 AOD package under the sibling `backups/NotchNowPlaying-0.1.124-before-mengo-20261005` directory.

## Verified source and transport

Inspected the installed MeN Go 2.0.23 bundle (Cordova/WKWebView). Its QRCode and
MQRCode components POST the current `ek_login_token` to the corresponding
`https://men-go.tw/Platform/Htmlv2/` endpoint. Successful responses wrap an inner
JSON document containing a base64 JPEG in `QRCode`. The app repeats the request
every 300 seconds. This interval alone does not prove QR validity duration.

Using the user's existing session and mobile browser request headers, a test
MQRCode request returned HTTP 200, `ok=true`, a QR image, and no expired-ticket
flag. A request without mobile browser headers returned HTTP 403. This confirms
retrieval, but does not prove that the AOD presentation can pass a station reader.
Private test credentials, WebKit storage copy and response were removed locally
after verification. None were added to Git or build artifacts.

## Runtime

* A separate filter injects the bridge only into MeN Go. The document-start script
  observes its existing login storage writes and QR request endpoint. It does not
  make requests or poll the app. Login removal/clear deletes the saved session.
* The saved session stays inside MeN Go's application container in a 0700 directory,
  with file mode 0600 and protection until first device unlock. The bridge copies
  only the login token, QR endpoint kind and browser agent. These are never logged.
* The SpringBoard client uses that session on an explicit AOD QR-button press.
  Every open fetches a fresh image; no ticket cache is persisted. Fixed HTTPS
  endpoints, URL-encoded POST body, redirect denial and an ephemeral URL session
  limit the transport to the intended service.
* Requests time out; response/base64 lengths and decoded image dimensions are
  checked. Invalid responses or expired tickets show an error without an old code.
  Authentication errors direct the user back to MeN Go.
* While the panel is open, renew after 60 seconds and close after 90 seconds.
  The shorter renewal is a conservative presentation policy, not a claim about
  the server's QR expiration. Both one-shot timers use the common run-loop modes.
* Close, pocket/cover blanking, manual wake, unlock and disabling the feature
  cancel the task, invalidate the session/timers, release the image and window.
  Generation checks reject callbacks from a previous presentation.
* The entry exists only in the active music AOD. The QR panel uses white backing
  and nearest-neighbor image scaling. The existing 30-second whole-surface black
  rest and physical pixel offset also apply to this window.
* Temporarily request 180 nits; preserve incoming ambient targets and restore
  their latest value (or the manual baseline) on close. The system brightness
  preference is unchanged. Music progress, content animations, next artwork and
  charging animation pause while the ticket panel covers them.

## Checks and remaining device validation

The embedded JavaScript bridge test exercises existing login, new login, allowed
endpoint capture, unrelated storage, untrusted endpoint, logout/clear and duplicate
injection. The Foundation test checks nested/string JSON, malformed types,
authentication errors, expiration, invalid/oversized images and form encoding.
GitHub Actions compiles normal/AOD variants and verifies all three arm64e modules.

Device validation still needs: reopen MeN Go after installation, display its QR
page once, open the AOD entry, confirm a fresh image, close/cover/unlock cleanup,
60-second renewal and 90-second close. Actual gate scanning and power savings
remain unmeasured.

## Build and installation

GitHub Actions run `37310766615` passed both normal and AOD jobs for source
`ff80e8bfcc3d2117ce2762f55413aea4b0b1a799`. Installed 0.1.125 AOD via dpkg and
reloaded SpringBoard successfully. Package SHA-256:
`d6cdb35647cbd2b7cdd80d2b50c83f9009a79da316b5fdd373aa9e69151f33f3`.

The user explicitly confirmed the desired entry behavior: a button to choose
whether to open the ticket. This implementation requests only after that press.
MeN Go was terminated once after installation so its next launch loads the bridge.
Initial login synchronization and AOD button/image testing await the user.

## 0.1.126 entry visibility correction

The user could not see the entry in 0.1.125. While the user kept the phone in AOD,
diagnostics reported `MengoEntryVisible=1`, `UIVisible=1`, active CoverSheet/AOD,
and no pocket suspension or revealed controls. Thus the eligibility flag did not
establish actual visibility. The entry used a separate UIWindow, unlike the music
content that already renders inside the CoverSheet host.

Replace that window with a transparent UIView attached directly to the same
visible host. Bring it above the blackout/player siblings when reconciling. The
closed overlay accepts only the button rectangle; the open panel accepts its
bounds. Detach/release it on AOD exit, blanking or manual wake. Apply the existing
pixel shift/rest to the overlay layer. New diagnostics record host attachment and
button frame, rather than relying only on eligibility. Physical visibility and
tap testing remain pending until the new build is installed.

Build `37311665848` passed normal and AOD jobs for source
`6b72d29f9265871eeca0402cca69a0b6c38cd798`. Installed 0.1.126 via dpkg and reloaded
SpringBoard successfully. Package SHA-256:
`8f84a1396d51529616aa3acf3e28608a391b8d2861bb029f9d7477b04b29f616`.
Before installation, the device already held a synced MeN Go session with
`MQRCode` endpoint and mode 0600, owned by mobile. No re-login is needed solely
for this UI correction. Awaiting physical button and ticket display validation.

## 0.1.127 touch routing

After 0.1.126 the user reported that tapping the entry did nothing. No ticket-open
or session-request state had been recorded. Route the entry and the open panel
through the existing AOD gesture window while retaining the visible host overlay.
Convert the actual control rectangles across views for routing. Ticket taps do
not toggle CoverSheet controls, and ticket gestures cannot skip tracks. Normal
notch tap/pan behavior remains available when the ticket panel is closed. Record
`MengoTouchRoutingActive` and `MengoLastTouchAction` without ticket/session data.

Actions run `37312454597` passed for source
`f03e6ae649b9bcfd37112f325e07a52752365877`. Installed 0.1.127 and reloaded SpringBoard.
Package SHA-256:
`191444b95a83a5f2e5bc59497f8009c4ce3dcf740af30c870bbdd1897778be1e`.
Actual tap delivery and image display still require the user's device test.

## 0.1.128 sensor classification

The user reports that ticket taps wake the normal screen. Existing device capture
`aod-0107-events.json` shows native backlight-off mode uses sensor display state 1,
digitizer disabled, tap-to-wake enabled; native backlight-on uses state 2 with
digitizer enabled and tap-to-wake disabled. A gesture window alone cannot convert
the low-power wake gesture into an ordinary UI touch.

The ticket controller now owns a separate BKSHIDUISensorService assertion while
its AOD entry is eligible. Runtime-checked setters request sensor display state 2,
ordinary digitizer input and no wake gestures. This is a sensor-mode request, not
a backlight/display transition, system preference change or source-number wake
suppression. The existing physical side-button wake code remains intact. Release
on blanking, AOD exit, feature disable or controller destruction restores native
mode arbitration. A host test uses the real assertion implementation against
mock native classes to check the requested fields, no duplicate request,
idempotent cleanup and destruction cleanup.

Primary runtime header references: MTACS/iOS-17-Runtime-Headers,
`BackBoardServices.framework/BKSHIDUISensorMode.h`, `BKSMutableHIDUISensorMode.h`
and `BKSHIDUISensorService.h` (retrieved via GitHub contents API).

Diagnostics add `MengoFullTouchAssertionActive` and the native `AODLastWakeSource`.
Actual prevailing sensor mode, delivered touches, side-key behavior and battery
cost remain device-test questions. Ordinary digitizer operation may increase
AOD power while this feature is enabled; no power saving claim is made.

Actions run `37392979023` passed both builds and the new assertion test for source
`9522e3f171d10414c7dd3f0272868b24a71f0e35`. Installed 0.1.128 and reloaded
SpringBoard. Package SHA-256:
`6cfb320c8e2ff948aa2d87c008a1fe0a6b6e0d190350ab73fc0835891a75e42a`.
Awaiting physical tap, ticket panel and side-button regression results.

## 0.1.129 native tap-to-wake routing

0.1.128 failed the same physical test. Device diagnostics showed the full-touch
assertion acquired, native wake source 9, and no ticket action. An acquired
assertion therefore was insufficient; do not treat its diagnostic flag as proof
that native tap handling changed. Remove the ineffective assertion/runtime files.

Runtime headers identify `SBTapToWakeController tapToWakeDidRecognize:` and
`SBFTapToWakeGestureRecognizer _succesfullyRecognizeFromEvent:`. Hook their
verified void/object and void/pointer signatures, preserving the originals.
During eligible music AOD only, retain a normalized digitizer coordinate from
the native recognition event for at most 0.5 seconds. Reject missing/nonfinite,
out-of-range, future or stale coordinates; optionally use a nonzero ordinary
UIGestureRecognizer location if available. Convert the point into the actual
CoverSheet host/control coordinates.

Only matching entry/panel taps go to the ticket controller before native wake.
Nonmatching, unavailable, inactive, covered and non-main-thread events invoke the
original native action. The side-button and backlight wake implementations are
unchanged. No always-on raw HID monitor or full digitizer assertion remains.
The new C policy test covers malformed coordinates and stale/future timestamps;
device testing must establish whether this native event contains usable positions.

Diagnostics: `MengoNativeWakeGestureHookInstalled`,
`MengoNativeWakeCoordinateHookInstalled`, `MengoWakeTapCoordinateAvailable`,
`MengoWakeTapPoint`, `MengoWakeTapConsumed`, and existing ticket-action fields.
