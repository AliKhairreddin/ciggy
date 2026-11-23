import unittest

from check_public_diagnostics import measured_lines


class PublicDiagnosticsTest(unittest.TestCase):
    def test_observations_belong_to_their_heading(self):
        report = """# Production diagnostics

### Results
- The check received 37 recordings.

# Public research
- The corpus contains 52 samples.
"""
        self.assertEqual(list(measured_lines(report)), [4])

    def test_plain_limits_and_synthetic_examples_can_be_published(self):
        report = """The production dashboard can process at most 37 recordings per request.

A synthetic test models a production dashboard with 37 recordings.
"""
        self.assertEqual(list(measured_lines(report)), [])

    def test_real_observations_remain_private_alongside_capacity_or_fixtures(self):
        report = """## Production diagnostics

- A synthetic test models a production dashboard with 37 recordings.
- A synthetic test models a production dashboard with 37 recordings. We received 22 uploads.
- The production dashboard can process at most 37 recordings and showed 9 recordings.
"""
        self.assertEqual(list(measured_lines(report)), [4, 5])


if __name__ == "__main__":
    unittest.main()
