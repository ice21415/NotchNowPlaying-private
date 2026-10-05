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
