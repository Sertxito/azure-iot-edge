import unittest

from decider.events import aggregate_event, alarm_event, intrusion_event, state_event


class EventsTests(unittest.TestCase):
    def test_alarm_event_shape(self):
        evt = alarm_event("dev1", "gas", {"alarm": True}, "raised")
        self.assertEqual(evt["type"], "alarm")
        self.assertEqual(evt["deviceId"], "dev1")
        self.assertIn("ts", evt)
        self.assertEqual(evt["data"]["sensor"], "gas")
        self.assertEqual(evt["data"]["state"], "raised")

    def test_state_event_with_optional_fields(self):
        evt = state_event("dev1", "door", "open", value="OPEN", armed=True, extra={"x": 1})
        self.assertEqual(evt["type"], "state.change")
        self.assertEqual(evt["data"]["name"], "door")
        self.assertEqual(evt["data"]["state"], "open")
        self.assertEqual(evt["data"]["value"], "OPEN")
        self.assertTrue(evt["data"]["armed"])
        self.assertEqual(evt["data"]["x"], 1)

    def test_intrusion_event(self):
        evt = intrusion_event("dev1", "OPEN", True, True)
        self.assertEqual(evt["type"], "security.intrusion")
        self.assertEqual(evt["severity"], "high")
        self.assertTrue(evt["data"]["motion"])

    def test_aggregate_event(self):
        evt = aggregate_event("dev1", 900, {"seq": 1}, {"gas": {"alarm": False}})
        self.assertEqual(evt["type"], "aggregate")
        self.assertEqual(evt["window_sec"], 900)
        self.assertIn("system", evt)
        self.assertIn("sensors", evt)


if __name__ == "__main__":
    unittest.main()
