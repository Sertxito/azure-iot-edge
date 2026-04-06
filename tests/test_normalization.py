import unittest

from bridge.mqtt.main import is_sensorsim_like, to_sensorsim_like
from decider.main import normalize


class NormalizationTests(unittest.TestCase):
    def test_bridge_detects_sensorsim_like(self):
        payload = {
            "deviceId": "dev1",
            "sensors": {
                "gas": {"analog": 100, "alarm": False},
                "pir": {"motion": False},
            },
        }
        self.assertTrue(is_sensorsim_like(payload))

    def test_bridge_normalizes_raw(self):
        raw = {
            "deviceId": "dev1",
            "sensors": {
                "motion": True,
                "gas": True,
                "ldr_raw": 250,
                "temperature": 23.5,
                "humidity": 55.0,
                "door": "OPEN",
                "touch": True,
            },
        }
        out = to_sensorsim_like(raw)
        self.assertEqual(out["deviceId"], "dev1")
        self.assertTrue(out["sensors"]["pir"]["motion"])
        self.assertTrue(out["sensors"]["gas"]["alarm"])
        self.assertEqual(out["sensors"]["light"]["analog"], 250)
        self.assertEqual(out["_meta"]["door"], "OPEN")
        self.assertTrue(out["_meta"]["touch"])

    def test_decider_normalize_preserves_sensorsim_like(self):
        payload = {
            "deviceId": "dev1",
            "sensors": {
                "gas": {"analog": None, "alarm": False},
                "pir": {"motion": False},
                "dht11": {"temp_c": 20.0, "humidity": 50.0},
            },
            "_meta": {"door": "CLOSED", "touch": False},
        }
        out = normalize(payload)
        self.assertEqual(out["deviceId"], "dev1")
        self.assertIn("_meta", out)
        self.assertEqual(out["_meta"]["door"], "CLOSED")


if __name__ == "__main__":
    unittest.main()
