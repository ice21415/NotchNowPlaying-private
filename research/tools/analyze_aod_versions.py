"""Compare two private, matched AOD battery phases. Never infer causality."""
import argparse
import bisect
import json
import math
import statistics
from pathlib import Path


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def read_records(path):
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]


def phase(samples, checks, version, warmup=120):
    if not samples or not checks:
        return {"verified": False, "reasons": ["Missing battery samples or condition checks."]}
    checks = sorted(checks, key=lambda row: row["unix_time"])
    times = [row["unix_time"] for row in checks]
    start = min(row["unix_time"] for row in samples) + warmup
    valid, conditions, reasons = [], [], set()
    for row in samples:
        stamp = row["unix_time"]
        if stamp < start:
            continue
        index = bisect.bisect_left(times, stamp)
        adjacent = checks[max(0, index - 1):min(len(checks), index + 1)]
        failure = False
        if index == 0 or index == len(checks) or any(abs(check["unix_time"] - stamp) > 25 for check in adjacent):
            reasons.add("Battery readings lack nearby condition checks.")
            failure = True
        for check in adjacent:
            pid = check.get("SpringBoardPID")
            if not pid or check.get("DiagnosticFlushPID") != pid or check.get("Phase7FixedBrightnessPID") != pid:
                reasons.add("Diagnostic state is missing or belongs to another SpringBoard process.")
                failure = True
            if check.get("version") != version:
                reasons.add("Installed version differs from the expected phase.")
                failure = True
            if check.get("Phase7AODPresentationActive") != 1 or check.get("LogicalLockState") != 1:
                reasons.add("AOD or logical lock was inactive.")
                failure = True
            if check.get("PocketUISuspended") != 0 or check.get("MengoTicketOpen") != 0:
                reasons.add("Screen-cover or ticket-panel state differs from the idle AOD test.")
                failure = True
            nits = check.get("Phase7FixedBrightnessAppliedNits")
            if check.get("Phase7FixedBrightnessActive") != 1 or not finite_number(nits) or nits <= 0:
                reasons.add("Accepted brightness override was not verified.")
                failure = True
            if check.get("AODAmbientSensorActive") not in (0, 1) or check.get("MengoNativeSensorPolicyActive") not in (0, 1):
                reasons.add("Sensor mode is unknown.")
                failure = True
        current, voltage = row.get("InstantAmperage"), row.get("Voltage")
        if row.get("IsCharging") is not False or row.get("ExternalConnected") is not False:
            reasons.add("Charging/disconnected state was not verified.")
            failure = True
        if not finite_number(current) or not finite_number(voltage) or current >= 0 or voltage <= 0:
            reasons.add("Discharge current or voltage is invalid.")
            failure = True
        if not finite_number(row.get("Temperature")) or not finite_number(row.get("UpdateTime")):
            reasons.add("Temperature or battery-driver update time is missing.")
            failure = True
        if not failure:
            valid.append(row)
            conditions.extend(adjacent)
    output = {"version": version, "valid_poll_count": len(valid)}
    if valid:
        power = [-row["InstantAmperage"] * row["Voltage"] / 1e6 for row in valid]
        updates = {row["UpdateTime"] for row in valid}
        nits = [check["Phase7FixedBrightnessAppliedNits"] for check in conditions]
        mode = {(check["AODAmbientSensorActive"], check["MengoNativeSensorPolicyActive"]) for check in conditions}
        temperatures = [row["Temperature"] / 100 for row in valid]
        output.update(mean_w=statistics.mean(power), median_w=statistics.median(power),
                      poll_stdev_w=statistics.stdev(power) if len(power) > 1 else None,
                      distinct_driver_updates=len(updates), mean_nits=statistics.mean(nits),
                      nits_range=[min(nits), max(nits)], sensor_modes=sorted(mode),
                      mean_temperature_c=statistics.mean(temperatures),
                      temperature_range_c=[min(temperatures), max(temperatures)],
                      sampled_span_seconds=valid[-1]["unix_time"] - valid[0]["unix_time"])
        if len(valid) < 60 or len(updates) < 10 or output["sampled_span_seconds"] < 600:
            reasons.add("Too few readings, driver updates or elapsed time for comparison.")
        if max(nits) - min(nits) > 2:
            reasons.add("Brightness changed materially within the phase.")
        if max(temperatures) - min(temperatures) > 1:
            reasons.add("Battery temperature did not remain stable within the phase.")
        if len(mode) != 1:
            reasons.add("Sensor mode changed within the phase.")
    else:
        reasons.add("No usable readings remain.")
    output["verified"] = not reasons
    output["reasons"] = sorted(reasons)
    return output


def compare(old, new):
    reasons = []
    if not old["verified"] or not new["verified"]:
        reasons.append("One or both phases failed verification.")
    else:
        if abs(old["mean_nits"] - new["mean_nits"]) > 2:
            reasons.append("Brightness differs between versions.")
        if abs(old["mean_temperature_c"] - new["mean_temperature_c"]) > 1:
            reasons.append("Mean battery temperature differs by more than 1 C.")
        if old["sensor_modes"] != new["sensor_modes"]:
            reasons.append("Sensor modes differ between versions.")
    result = {"conditions_matched": not reasons, "reasons": reasons,
              "limitations": ["Whole-device battery gauge estimates, not plugin-only power.",
                              "Polling values are correlated; distinct driver updates are not independent trials.",
                              "Short state changes between condition checks can be missed.",
                              "Playlist, audio, connectivity and interruptions require human confirmation.",
                              "One matched pair is descriptive; repeated alternating phases are required for a savings claim."]}
    if not reasons:
        result["observed_new_minus_old_w"] = new["mean_w"] - old["mean_w"]
        result["observed_difference_percent"] = (new["mean_w"] / old["mean_w"] - 1) * 100
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("old_samples", "old_checks", "new_samples", "new_checks"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--old-version", default="0.1.138")
    parser.add_argument("--new-version", default="0.1.139")
    args = parser.parse_args()
    old = phase(read_records(args.old_samples), read_records(args.old_checks), args.old_version)
    new = phase(read_records(args.new_samples), read_records(args.new_checks), args.new_version)
    print(json.dumps({"old": old, "new": new, "comparison": compare(old, new)}, indent=2, ensure_ascii=False))
