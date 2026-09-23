#!/usr/bin/env python3
"""Bounded SSH/SCP orchestration for one NotchNowPlaying screenshot.

The script deliberately uses the existing preference-triggered SpringBoard
helper. It never wakes, unlocks, changes display policy, or presses a device
button. SSH keys are preferred; otherwise OpenSSH prompts for the password.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import struct
import subprocess
import sys
import time
import uuid
import zlib
import plistlib


DOMAIN = "com.user.notchnowplaying"
DIAGNOSTIC_DOMAIN_PATH = "/var/mobile/Library/Preferences/com.user.notchnowplaying.diagnostics.plist"
REMOTE_RESULT_ROOT = "/var/mobile/Library/NotchNowPlaying/ssh-screenshot-result.plist"


def run_process(argv: list[str], cwd: pathlib.Path | None = None) -> int:
    print("+", " ".join(argv), flush=True)
    return subprocess.run(argv, cwd=cwd, check=False).returncode


def ssh_command(target: str, command: str) -> int:
    return run_process([
        "ssh", "-tt", "-o", "ConnectTimeout=8",
        "-o", "StrictHostKeyChecking=no", target, command,
    ])


def scp_from(target: str, remote_path: str, local_path: pathlib.Path) -> int:
    local_path.parent.mkdir(parents=True, exist_ok=True)
    return run_process([
        "scp", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=no",
        f"{target}:{remote_path}", str(local_path),
    ])


def parse_png(data: bytes) -> dict[str, object]:
    """Validate and sample common 8-bit RGB/RGBA PNGs without third-party libs."""
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        return {"valid": False, "reason": "bad PNG signature", "bytes": len(data)}
    offset = 8
    idat = bytearray()
    width = height = bit_depth = color_type = None
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        if payload_end + 4 > len(data):
            return {"valid": False, "reason": "truncated chunk", "bytes": len(data)}
        payload = data[payload_start:payload_end]
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, _ = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
        offset = payload_end + 4
    if not width or not height or bit_depth != 8 or color_type not in (2, 6):
        return {
            "valid": False,
            "reason": "unsupported PNG format",
            "bytes": len(data),
            "width": width,
            "height": height,
            "bitDepth": bit_depth,
            "colorType": color_type,
        }
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as error:
        return {"valid": False, "reason": f"zlib decode failed: {error}", "bytes": len(data)}
    expected = height * (stride + 1)
    if len(raw) < expected:
        return {"valid": False, "reason": "truncated scanlines", "bytes": len(data), "width": width, "height": height}

    previous = bytearray(stride)
    non_black = 0
    max_rgb = 0
    for row in range(height):
        filter_type = raw[row * (stride + 1)]
        encoded = raw[row * (stride + 1) + 1:(row + 1) * (stride + 1)]
        current = bytearray(stride)
        for index, value in enumerate(encoded):
            left = current[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                result = value
            elif filter_type == 1:
                result = value + left
            elif filter_type == 2:
                result = value + up
            elif filter_type == 3:
                result = value + ((left + up) // 2)
            elif filter_type == 4:
                estimate = left + up - upper_left
                paeth_left = abs(estimate - left)
                paeth_up = abs(estimate - up)
                paeth_upper_left = abs(estimate - upper_left)
                predictor = left if paeth_left <= paeth_up and paeth_left <= paeth_upper_left else (up if paeth_up <= paeth_upper_left else upper_left)
                result = value + predictor
            else:
                return {"valid": False, "reason": f"unsupported filter {filter_type}", "bytes": len(data)}
            current[index] = result & 0xFF
        for index in range(0, stride, channels):
            pixel_max = max(current[index:index + 3])
            if pixel_max:
                non_black += 1
            max_rgb = max(max_rgb, pixel_max)
        previous = current
    return {
        "valid": True,
        "bytes": len(data),
        "width": width,
        "height": height,
        "bitDepth": bit_depth,
        "colorType": color_type,
        "pixels": width * height,
        "nonBlackPixels": non_black,
        "maxRGB": max_rgb,
    }


def safe_id(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_-]", "", value)
    return value[:64] or uuid.uuid4().hex


def load_diagnostics(path: pathlib.Path) -> dict:
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
        return value if isinstance(value, dict) else {}
    except Exception as error:
        print(f"diagnostics parse failed: {error}", file=sys.stderr)
        return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", default="root@TAILSCALE_IP_REDACTED")
    parser.add_argument("--session-dir", type=pathlib.Path)
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--request-id")
    parser.add_argument("--label", default="capture")
    args = parser.parse_args()

    request_id = safe_id(args.request_id or f"{args.label}-{dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S')}-{uuid.uuid4().hex[:8]}")
    session_dir = args.session_dir or pathlib.Path("research") / "runtime" / f"phase7.9-{request_id}"
    session_dir.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "requestID": request_id,
        "label": args.label,
        "target": args.target,
        "hostStartUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
        "capture": "NOT_STARTED",
        "retrieval": "NOT_STARTED",
        "content": "NOT_TESTED",
    }

    print("Preflight: verify SSH and injected diagnostic helper.")
    if ssh_command(args.target, f"defaults read {DOMAIN} Enabled; defaults read {DOMAIN} ExperimentalLockedVisible; defaults read {DOMAIN} SSHScreenshotRequest; exit") != 0:
        manifest["preflight"] = "FAIL"
        (session_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return 1

    print(f"Triggering one-shot request id={request_id}")
    trigger = f"defaults write {DOMAIN} SSHScreenshotRequestID -string {request_id}; defaults write {DOMAIN} SSHScreenshotRequest -bool true; exit"
    if ssh_command(args.target, trigger) != 0:
        manifest["capture"] = "FAIL"
        (session_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return 1

    poll = (
        "i=0; found=1; "
        f"while [ $i -lt {max(1, args.timeout)} ]; do "
        f"defaults read {DOMAIN} SSHScreenshotResult 2>/dev/null | grep -F '{request_id}' >/dev/null "
        "&& found=0 && break; sleep 1; i=$((i+1)); done; exit $found"
    )
    manifest["requestSentUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
    if ssh_command(args.target, poll) != 0:
        manifest["capture"] = "TIMEOUT"
        (session_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return 2
    manifest["capture"] = "PASS"

    diagnostics_path = session_dir / "diagnostics.plist"
    if scp_from(args.target, DIAGNOSTIC_DOMAIN_PATH, diagnostics_path) != 0:
        manifest["retrieval"] = "FAIL"
        (session_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return 3
    diagnostics = load_diagnostics(diagnostics_path)
    result = diagnostics.get("SSHScreenshotResult") if isinstance(diagnostics.get("SSHScreenshotResult"), dict) else {}
    capture_diagnostics = diagnostics.get("SSHScreenshotCaptureDiagnostics") if isinstance(diagnostics.get("SSHScreenshotCaptureDiagnostics"), dict) else {}
    manifest["result"] = result
    manifest["captureDiagnostics"] = capture_diagnostics
    manifest["injection"] = {
        "tweakLoaded": diagnostics.get("TweakLoaded"),
        "springBoardPID": diagnostics.get("SpringBoardPID"),
    }
    events = diagnostics.get("DiagnosticLogEvents") if isinstance(diagnostics.get("DiagnosticLogEvents"), list) else []
    manifest["relevantEvents"] = [event for event in events if isinstance(event, dict) and ("SCREENSHOT_CAPTURE" in str(event.get("event")) or "logical-lock" in str(event.get("event")) or "logical-unlock" in str(event.get("event")))]

    if result.get("requestID") != request_id:
        manifest["retrieval"] = "INSUFFICIENT_EVIDENCE"
    else:
        manifest["retrieval"] = "PASS"

    remote_path = result.get("sshPath")
    image_path = session_dir / f"{request_id}.png"
    if isinstance(remote_path, str) and remote_path:
        if scp_from(args.target, remote_path, image_path) == 0 and image_path.exists():
            image_data = image_path.read_bytes()
            manifest["image"] = parse_png(image_data)
            manifest["content"] = "PASS" if manifest["image"].get("valid") and manifest["image"].get("nonBlackPixels", 0) else "FAIL"
        else:
            image_path.unlink(missing_ok=True)

    preview = diagnostics.get("SSHScreenshotPreviewPNG")
    if isinstance(preview, bytes) and preview:
        preview_path = session_dir / f"{request_id}-preview.png"
        preview_path.write_bytes(preview)
        manifest["preview"] = parse_png(preview)
        if manifest["content"] == "NOT_TESTED":
            manifest["content"] = "PASS" if manifest["preview"].get("valid") and manifest["preview"].get("nonBlackPixels", 0) else "FAIL"

    manifest["hostEndUTC"] = dt.datetime.now(dt.timezone.utc).isoformat()
    (session_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, default=str), encoding="utf-8")
    print(json.dumps({key: manifest.get(key) for key in ("requestID", "capture", "retrieval", "content", "image", "preview", "injection")}, indent=2, default=str))
    return 0 if manifest["capture"] == "PASS" and manifest["retrieval"] == "PASS" and manifest["content"] == "PASS" else 4


if __name__ == "__main__":
    raise SystemExit(main())
