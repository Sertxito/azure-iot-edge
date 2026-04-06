import unittest

from decider.rules import hum_band, is_intrusion, light_bucket, temp_band


class RulesTests(unittest.TestCase):
    def test_light_bucket_ranges(self):
        self.assertEqual(light_bucket(100), "bright")
        self.assertEqual(light_bucket(300), "ambient")
        self.assertEqual(light_bucket(700), "dark")

    def test_light_bucket_unknown(self):
        self.assertEqual(light_bucket(None), "unknown")
        self.assertEqual(light_bucket("bad"), "unknown")

    def test_temp_band_ranges(self):
        self.assertEqual(temp_band(10), "low")
        self.assertEqual(temp_band(20), "normal")
        self.assertEqual(temp_band(35), "high")

    def test_hum_band_ranges(self):
        self.assertEqual(hum_band(10), "low")
        self.assertEqual(hum_band(50), "normal")
        self.assertEqual(hum_band(90), "high")

    def test_intrusion_rule(self):
        self.assertTrue(is_intrusion("OPEN", True))
        self.assertFalse(is_intrusion("CLOSED", True))
        self.assertFalse(is_intrusion("OPEN", False))


if __name__ == "__main__":
    unittest.main()
