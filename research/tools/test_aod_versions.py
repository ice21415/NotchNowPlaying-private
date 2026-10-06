import copy
import unittest
from analyze_aod_versions import phase, compare


def fixtures(version="0.1.138", current=-200):
    samples = [{"unix_time": stamp + 1, "InstantAmperage": current, "Voltage": 4000,
                "IsCharging": False, "ExternalConnected": False, "Temperature": 3000,
                "UpdateTime": stamp // 30} for stamp in range(0, 901, 10)]
    checks = [{"unix_time": stamp, "version": version, "SpringBoardPID": 123,
               "DiagnosticFlushPID": 123, "Phase7FixedBrightnessPID": 123,
               "Phase7AODPresentationActive": 1, "LogicalLockState": 1,
               "PocketUISuspended": 0, "MengoTicketOpen": 0,
               "Phase7FixedBrightnessActive": 1, "Phase7FixedBrightnessAppliedNits": 90,
               "AODAmbientSensorActive": 1, "MengoNativeSensorPolicyActive": 1}
              for stamp in range(0, 911, 10)]
    return samples, checks


class ComparisonTests(unittest.TestCase):
    def test_matched_pair_has_only_observed_difference(self):
        old = phase(*fixtures(), "0.1.138")
        new = phase(*fixtures("0.1.139", -180), "0.1.139")
        result = compare(old, new)
        self.assertTrue(result["conditions_matched"])
        self.assertAlmostEqual(result["observed_difference_percent"], -10)
        self.assertNotIn("savings_percent", result)

    def test_bad_state_prevents_comparison(self):
        for key, value in [("DiagnosticFlushPID", 122), ("Phase7FixedBrightnessPID", None),
                           ("Phase7AODPresentationActive", 0), ("LogicalLockState", 0),
                           ("PocketUISuspended", 1), ("MengoTicketOpen", 1),
                           ("Phase7FixedBrightnessAppliedNits", None), ("version", "0.1.139")]:
            with self.subTest(key=key):
                samples, checks = fixtures()
                checks[30][key] = value
                result = phase(samples, checks, "0.1.138")
                self.assertFalse(result["verified"])

    def test_charging_unknown_and_stale_gauge_are_rejected(self):
        for key, value in [("IsCharging", True), ("ExternalConnected", None),
                           ("InstantAmperage", 0), ("Temperature", None)]:
            samples, checks = fixtures()
            samples[30][key] = value
            self.assertFalse(phase(samples, checks, "0.1.138")["verified"])
        samples, checks = fixtures()
        for row in samples:
            row["UpdateTime"] = 0
        self.assertFalse(phase(samples, checks, "0.1.138")["verified"])

    def test_condition_gaps_and_short_phase(self):
        samples, checks = fixtures()
        del checks[25:35]
        self.assertFalse(phase(samples, checks, "0.1.138")["verified"])
        samples, checks = fixtures()
        self.assertFalse(phase(samples[:35], checks[:35], "0.1.138")["verified"])

    def test_within_phase_temperature_drift(self):
        samples, checks = fixtures()
        samples[30]["Temperature"] = 3200
        self.assertFalse(phase(samples, checks, "0.1.138")["verified"])

    def test_cross_phase_mismatch(self):
        old = phase(*fixtures(), "0.1.138")
        for key, value in [("mean_nits", 95), ("mean_temperature_c", 32),
                           ("sensor_modes", [(1, 0)])]:
            new = copy.deepcopy(old)
            new[key] = value
            result = compare(old, new)
            self.assertFalse(result["conditions_matched"])
            self.assertNotIn("observed_difference_percent", result)

    def test_warmup_does_not_contaminate_phase(self):
        samples, checks = fixtures()
        samples[0]["IsCharging"] = True
        checks[0]["Phase7AODPresentationActive"] = 0
        self.assertTrue(phase(samples, checks, "0.1.138")["verified"])

    def test_nonfinite_and_boolean_measurements_are_invalid(self):
        for value in (float("nan"), float("inf"), True):
            for key in ("InstantAmperage", "Voltage", "Temperature", "UpdateTime"):
                samples, checks = fixtures()
                samples[30][key] = value
                self.assertFalse(phase(samples, checks, "0.1.138")["verified"])
            samples, checks = fixtures()
            checks[30]["Phase7FixedBrightnessAppliedNits"] = value
            self.assertFalse(phase(samples, checks, "0.1.138")["verified"])


if __name__ == "__main__":
    unittest.main()
