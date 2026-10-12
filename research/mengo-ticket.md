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

Read at most 16 event nodes, including finger children when the digitizer parent
has no usable coordinate. Record the raw event type and last examined X/Y to
distinguish missing positions from hit-test conversion problems. Timer tests now
wait against monotonic uptime and verify the repeated-sample deadline directly;
post-deadline checks allow host scheduling jitter without permitting a reset timer
to masquerade as a preserved deadline. No production cover/lock timing changed.

Actions `37394813505` passed normal and AOD builds for source
`e9aa39164faadabfd8672c3f04847b97d2f4b609`. Installed 0.1.129 and reloaded
SpringBoard. SHA-256:
`0286b134311226a1d9699fe255a2134273963e3cabf1701684d38a72b6fa368c`.
Post-install device read confirmed both native wake/coordinate hooks installed,
the ineffective full-touch assertion inactive, and SpringBoard PID 26386.
Physical coordinate delivery and button handling still await the user's test.

## 0.1.130 and 0.1.131 results

0.1.130 added declared pixel/screen-point conversion and UIKit touch capture.
Actions `37396862156` passed both variants, source
`ddb5cdecb4586eb1880e357cf04648d187f63207`; installed package SHA-256
`69f02e5bcacfa92bd593979cd9653c8be9bd5535b5b0a5c5e5c76bb06c8c7185`.
The user reports the entry is complete, but wake taps still fail. Actual captured
UIKit position was `{375,455.3333}`, raw `{1125,1366}`, versus entry screen frame
`{{299,680},{52,52}}`. Screen bounds are 375x812, native bounds 1080x2340, scale 3.
This wake-event position cannot reliably identify the user's QR-button press.

0.1.131 replays SpringBoard's sensor-only update with the ordinary-input state,
preserving the actual backlight state. The policy restores the current native
sensor state on exit and latches off if replay changes backlight state. Host tests
check physical-state preservation, native update forwarding, current-state restore,
destruction cleanup and failure-loop avoidance. Actions `37398128772` passed both
variants, source `3f171917d5dd1fa3c57f2debe27d69cc68126682`; installed SHA-256
`9e693ce0a505226645d33f8ed2b5299d2662c49148c1e9b42552feb3636da96c`.
Device read showed policy active, digitizer enabled, tap-to-wake flag off, backlight
state 4 before and after. The user still reports wake; observed wake source changed
to 13. Ordinary input is now configured, but a separate touch-to-wake path remains.

## 0.1.132 early input dispatch

Intercept the actual SpringBoard application subclass's `sendEvent:` and its
runtime-verified `__handleHIDEvent:withUIEvent:` callback. Inspect ordinary UI touch
coordinates before SpringBoard consumes the first touch as wake. Only a single
finger starting within the entry/panel is owned. Consume that touch sequence;
activate on release inside the region with under 18 points of movement. Other
touches, keyboard/button events, inactive AOD and covered screens retain native
dispatch. No global wake-source suppression is introduced.

Diagnostics include early HID-hook availability, actual early touch point and
matched-region state. Real delivery/position and side-key/cover regressions remain
device-test requirements. Keeping ordinary digitizer input enabled while this
feature is visible can add power cost; it has not been measured.

Actions `37399670027` passed both variants, source
`e59919ca477571f23ec0e99c78c3418c2a362857`. Installed 0.1.132 and reloaded
SpringBoard. SHA-256:
`e23eb3d05ed0f031c52c8764cedbf29db78d205a2c27f9c87d8afc4516174972`.
Device confirms early HID and application event hooks installed. Physical tap
coordinates, successful region match and real ticket image display remain pending.

## 0.1.133 verified event source

After 0.1.132 the user reports no reaction; no UIKit early-contact fields appeared.
A finite standalone monitor, signed only with the HID event-monitor entitlement,
received real digitizer contacts while the user pressed the AOD entry. Coordinates
`{0.8578033,0.8593140}` project to `{321.676,697.763}` inside its screen rectangle.
Both down/up transitions and finger child nodes were present. The first timed
capture missed the user; the second capture supplied this evidence.

0.1.133 adds an AOD-scoped event monitor using that verified source. It reacts to
contact transitions only, routes a press/release with under 18 points displacement,
and unregisters/unschedules/releases the client when the entry becomes ineligible.
The user confirmed the button now opens the ticket. Actions `37401355040` passed
both builds, source `5fb4c41a98dcac1b985748f1febf8d2e402fd4b9`; installed SHA-256
`296d9c5745b489f8f3554d36e21567661c47239e980b52c9de0ea8ba5688c887`.
Later diagnostic read showed session available and last action close, supporting
the user's successful interaction report; image availability had reset on close.

## 0.1.134 countdown, verification and gesture wake wallpaper

Show monotonic renewal (60 seconds after successful fetch) and panel-close
(90 seconds after opening) countdowns. A single 1-second timer runs only for the
open panel and is invalidated on close/blanking/exit. Renewal is not labeled QR
expiration because the service has not supplied a verified QR-validity deadline.

Decode each freshly returned image once off the main thread with Core Image.
Accept a decoded QR string or binary error-corrected payload as structural QR
readability; log only the boolean, never payloads. This establishes readable QR
structure, not issuer signature validity or station acceptance. Real gate scanning
still needs user validation. Dynamic official-app/plugin codes may differ between
separate requests, so visual equality is not a validation rule.

Installed MeN Go's MQRCode template labels an expired ticket as exit/alight-only
and still shows the issued QR. Match that behavior with a warning rather than
rejecting an exit-capable image. Tests cover the warning and preserved image.

The user also reports a black wallpaper after gesture wake. Wake cleanup now
recognizes an active AOD even when the older suppressed-blank pending flag has
already cleared. Clear the plugin window/root background and remove the CoverSheet
masks; black dedicated presentation applies only to actual AOD. Existing notification
and charging wake guards execute before this cleanup path. A C policy test covers
pending-free AOD wake, inactive/unlocked exclusions and covered-screen exclusions.

Actions `37402835428` passed both variants for source
`7ff7fcead9727165608c9bb55e9f9db5aab55876`. Installed 0.1.134; SHA-256
`7062acd623a24ef563ba287a352643c64726083dd4528b990a9d6870f6696d33`.

## 0.1.135 outside touch wake and pixel diagnostics

The user reports outside taps no longer wake with ordinary input enabled.
Retain a contact-down position even outside the closed entry. On a low-displacement
release outside the entry, clear AOD through its existing wake cleanup and call
SpringBoard's runtime-verified full-screen-wake method with the ordinary-touch
source 13 observed on this device. Entry/panel controls remain routed to the ticket
controller. Side-button dispatch remains native. No outside wake is synthesized
while the ticket panel is open.

The entry, QR image, countdown and panel controls already share the overlay layer
included in the 30-second physical pixel shift and black rest. Add layer transform,
X/Y and presentation-opacity diagnostics to confirm that behavior on device.
This protection reduces OLED aging risk; no zero-burn-in guarantee is made.

Actions `37403863322` passed both variants for source
`3e31cc4988425664e284b6bd2672f18ded447934`. Installed 0.1.135; SHA-256
`dd695b3430d36b2c15c98c98c1e3ccca3037513ac6e9b45da98a22fa63cd579a`.
Post-install read retained QR readability true and exit-only false from the prior
successful fetch. The phone was outside AOD at that read, so no new overlay pixel
shift/rest sample was available. Current-build outside wake, wallpaper and pixel
behavior await the user's regression test.

## 0.1.136 crash recovery and client lifetime

0.1.135 caused Safe Mode. Immediately rolled back to the user's working 0.1.133
package and reloaded SpringBoard. Found the real system crash directory under
`/rootfs/var/mobile/Library/Logs/CrashReporter`. Kept the raw IPS only in ignored
local build-packages; no personal report contents were committed.

SpringBoard report 2026-10-06 13:37 shows EXC_BREAKPOINT/SIGTRAP and
`BUG IN CLIENT OF LIBPLATFORM: os_unfair_lock is corrupt`, with
`__IOHIDEventSystemClientGetService` under `__IOHIDEventSystemClientQueueCallback`.
Outside-tap wake synchronously ended AOD and released the monitor client inside
its event callback. IOKit then continued processing the retired client.

Move contact actions to main-queue blocks after callback return. On stop, mark
inactive and advance generation immediately, detach the CF client, then defer
unschedule/unregister/release. Retain the callback target precisely through that
teardown. Old-generation callbacks cannot affect a restarted session. Host tests
verify no teardown inside callback, target lifetime through unregister, single
cleanup and null-client handling.

Actions `37420279451` passed source
`9e45801ff2ff284a831c281148e4687c58889376`. Installed 0.1.136, SHA-256
`3328bcd11ec11eec24e867b62769f96de9ff6a3561972f0645d0ae6c6ff6d877`.
The user confirmed outside-tap wake no longer enters Safe Mode. Wallpaper still
remained black despite visible native Lock Screen UI.

## 0.1.137 complete native tap wake flow

During the user's black-wallpaper state, diagnostics report player hidden,
AOD presentation inactive, CoverSheet/status masks inactive, dedicated plugin
background clear, ticket closed and sensor override inactive. The masks have
therefore been removed. The direct backlight wake alone has not restored the
complete native wallpaper presentation.

Use the runtime-verified `SBLockScreenManager _wakeScreenForTapToWake` instead of
calling the backlight controller directly with source 13. This follows the native
Lock Screen tap wake flow and avoids hardcoding its backlight source. Retain
AOD cleanup and the deferred monitor lifetime fix. Physical wallpaper restoration
and side-key/ticket regression still require device testing.

Actions `37421289121` passed both AOD and normal jobs (normal passed after
rerunning the existing lock-observer timing failure). Source
`4c6a1393b300d49149dfc4bc766085af4e7c7c84`; AOD package SHA-256
`f90c2e60af886e12f9ad18829008c7a2a89e5135280a893d1165c733da8307f3`.
Installed 0.1.137; dpkg version and new SpringBoard PID 27905 confirmed. Physical
tap-wake wallpaper verification is pending user testing.

## Credential lifetime audit (installed MeN Go 2.0.23)

Static analysis of the installed app source map, SHA-256
`7ad0ba0c03b253f3286239499918fc198541bd111cc4c8102de6c8cf93d000c1`, found:

- `src/utils/storage.js`: Cordova/mobile uses plain localStorage get/set/remove.
  The time argument is used only in the website cookie branch. Login calls with
  `1y` therefore do not establish a one-year mobile credential lifetime.
- `src/App.vue`: startup invokes loginCheck, POSTs the stored token to
  `/Platform/Htmlv2/LoginCheck`, and removes local credentials on response.error
  after the user dismisses the dialog. Success does not save a replacement token.
- QR pages recognize `toekn_error`; CheckQRCode recognizes `token_error`.
  The plugin parser already recognizes both and displays a re-login message.
- No explicit refresh-token, expires_in or token_exp references were found in
  this source map. This is evidence about this client, not proof of all server
  capabilities. The server's absolute/idle expiry and whether validation extends
  a session cannot be determined from client code alone.

No logout, fabricated credential, clock alteration or ticket mutation was used.
No new authenticated network call was made in this audit. Current validity and
future expiry are separate questions; a successful QR request proves validity
only at the time of that request. Exact TTL requires server documentation or
controlled observations over time. Avoid background polling solely for this
purpose; record non-secret success/auth-failure times during normal QR use.

## 0.1.138 advance credential check

A live LoginCheck request using the existing phone session returned HTTP 200
and exactly {"ok":true}. Only response field types and boolean status were
printed. The temporary local session copy was deleted immediately afterward.

Add a credential status caption beside the QR entry. Check LoginCheck on AOD
entry when due and every 30 minutes while the entry remains active; reuse a
recent check across wake/respring. No QR image is fetched for preflight. Cancel
requests/timer when leaving AOD or entering covered-screen suspension. A failed
check means unknown, not expired; retain a known rejection until a successful
check or a new session. A new stored-session timestamp invalidates cached status.
Persist only session update timestamp, check/attempt times and classification;
never credential contents. Display the last confirmed time for valid login.
The caption shares the existing overlay's pixel shift and black-rest behavior.

Tests cover valid LoginCheck, both authentication-error spellings, explicit
LoginCheck error, conflicting success/error, unknown failure, null/array fields,
malformed JSON/proxy HTML and oversized response. Existing QR parsing tests remain.
These checks validate login only; ticket expiry and gate acceptance are separate.
Outside active music AOD there is no background checker or notification. This is
advance information, not a guarantee against revocation after a successful check.

Actions `37423765771` passed both variants for source
`d3ff0d1de2baa1a3932e7369c5a14983b49c4ced`. Installed 0.1.138, package SHA-256
`98e585138e5c2c1f31531b48d33cf6583b70537f3c6da0aa869a238ad90a06b5`.
Device confirms version 0.1.138, new SpringBoard PID 27967 and automatic preflight
caption "login valid" with the device check time 14:29. Physical caption layout
still requires user confirmation; invalid-login/network states were fixture-tested,
not induced on the live account.

## 0.1.140 scanner proximity must not blank an open QR panel

The user reported the screen blanking when bringing the displayed QR near a
reader. Pocket suspension previously applied to all AOD, including the ticket
panel, so cover/proximity detection could blank the screen and close that panel.

- An open ticket panel bypasses both cover and pocket suspension.
- On opening, stop the screen-cover and pocket observers, releasing plugin-owned
  proximity monitoring and native proximity assertion. Reconcile cannot reactivate
  those observers while the panel is open. This also stops cover accelerometer
  sampling during scanning; do not merely ignore a still-active sensor callback.
- On every panel close (including timeout), reconcile unconditionally so detection
  resumes even when shouldShow is false because the phone is currently covered.
- Preserve the panel's brightness boost during reconcile when automatic AOD
  brightness is disabled. QR lifetime/renewal, touch routing, side-key wake and
  pixel shifting remain unchanged.
- The shared C policy tests cover all 64 enable/lock/AOD/panel/cover/pocket states
  and explicitly check suppression while scanning and restoration after close.

Per the user's instruction, repository visibility was changed from PRIVATE to
PUBLIC before Actions compilation and then verified PUBLIC. Backup 0.1.139:
`backups/NotchNowPlaying-0.1.139-before-qr-cover-20261012` (bundle, source archive,
AOD package and saved preferences). Final code source
`8d2e0ecfc079892aedc5b78e061159a53430bf9d`; Actions run `38191188725`.
The earlier run `38191130160` was superseded and cancelled before deployment.
Physical scanner/covered-panel behavior and cover-mode restoration await testing.

Both Actions variants passed; the AOD job passed after rerunning the known
lock-observer timing assertion at line 48. AOD package SHA-256:
`939da30c264a69370ef2bf1a7007e7ce8c7b65ac19986ef35cc096b32f06c70b`.

Installed 0.1.140. The respring interrupted the SSH transport; reconnecting
confirmed dpkg version 0.1.140 and SpringBoard PID 45098. DiagnosticFlushPID is
also 45098, confirming the tweak loaded in that process. At inspection AOD and
QR are inactive, and AODCoverDetectionActive/PocketUISuspended are both zero.
MengoCoverBlankSuppressed is not yet emitted until the first panel transition;
no physical scanning test result has been received. User was asked to verify
covered/proximity behavior with QR open, then normal cover blanking after close.
