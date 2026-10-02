"""Summarize local, private battery logs; measurements are whole-device estimates."""
import argparse
import json
import statistics
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("samples", type=Path)
parser.add_argument("metadata", type=Path)
parser.add_argument("--warmup", type=float, default=60)
args = parser.parse_args()
records = [json.loads(line) for line in args.samples.read_text(encoding="utf-8").splitlines() if line.strip()]
phases = {}
current = None
for line in args.metadata.read_text(encoding="utf-8").splitlines():
    pieces = line.split()
    if len(pieces) == 2 and pieces[0] in {"A1", "A1_END", "B1", "B1_END", "B2", "B2_END", "A2", "A2_END"}:
        current = pieces[0]
        phases[current] = {"time": int(pieces[1])}
    elif current and "=" in line:
        key, value = line.split("=", 1)
        phases[current][key] = value

summary = {"raw_sample_count": len(records), "warmup_seconds": args.warmup, "phases": {}, "comparison": {}}
grouped = {"automatic": [], "manual": []}
for phase in ("A1", "B1", "B2", "A2"):
    if phase not in phases or phase + "_END" not in phases:
        continue
    begin, end = phases[phase], phases[phase + "_END"]
    usable, rejected, seen = [], 0, set()
    for record in records:
        if not begin["time"] + args.warmup <= record["unix_time"] < end["time"]:
            continue
        current_ma, voltage_mv = record.get("InstantAmperage"), record.get("Voltage")
        if record.get("IsCharging") or record.get("ExternalConnected") or current_ma is None or voltage_mv is None or current_ma >= 0 or voltage_mv <= 0:
            rejected += 1
            continue
        signature = (record.get("UpdateTime"), current_ma, voltage_mv)
        if signature in seen:
            continue
        seen.add(signature)
        usable.append(record)
    power = [-r["InstantAmperage"] * r["Voltage"] / 1e6 for r in usable]
    mode = "automatic" if phase.startswith("A") else "manual"
    expected = "1" if mode == "automatic" else "0"
    verified = end.get("AODAmbientSensorActive") == expected and end.get("AODAutomaticBrightnessEnabled") == expected and end.get("AODPixelShiftTimerActive") == "1" and end.get("LogicalLockState") == "1"
    info = {"start": begin, "end": end, "end_state_verified": verified, "distinct_gauge_records": len(usable), "invalid_samples": rejected}
    if power:
        info.update(mean_w=statistics.mean(power), median_w=statistics.median(power), stdev_w=statistics.stdev(power) if len(power) > 1 else None, min_w=min(power), max_w=max(power), mean_discharge_ma=statistics.mean(-r["InstantAmperage"] for r in usable), temperature_raw_range=[min(r["Temperature"] for r in usable), max(r["Temperature"] for r in usable)])
        if verified and not rejected:
            grouped[mode].extend(power)
    summary["phases"][phase] = info
for mode, power in grouped.items():
    if power:
        summary["comparison"][mode] = {"mean_w": statistics.mean(power), "median_w": statistics.median(power), "distinct_records": len(power), "stdev_w": statistics.stdev(power) if len(power) > 1 else None}
if all(grouped.values()):
    auto_mean, manual_mean = (statistics.mean(grouped[k]) for k in ("automatic", "manual"))
    summary["comparison"]["observed_automatic_minus_manual_w"] = auto_mean - manual_mean
    summary["comparison"]["observed_difference_percent"] = (auto_mean / manual_mean - 1) * 100
summary["limitations"] = ["Whole-device battery gauge estimate, not isolated sensor hardware power.", "Short phases and repeated gauge values limit sensitivity; descriptive differences do not establish causation.", "Brightness and AOD state are checked at phase boundaries, not continuously.", "Distinct records are not guaranteed statistically independent."]
print(json.dumps(summary, ensure_ascii=False, indent=2))
