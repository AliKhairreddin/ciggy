"""Security/format regression tests for the inert research-data interpreter."""

import unittest

from export_sed import parse_data_only


class StaticDecoderTests(unittest.TestCase):
    def test_simple_literals(self):
        stream = b"\x80\x03}q\x00X\x01\x00\x00\x00aq\x01K\x01s."
        self.assertEqual(parse_data_only(stream), {"a": 1})

    def test_executable_global_is_rejected_before_resolution(self):
        for global_name in [b"os\nsystem\n", b"builtins\neval\n", b"subprocess\nPopen\n"]:
            with self.subTest(global_name=global_name), self.assertRaisesRegex(ValueError, "Unsupported pickle global"):
                parse_data_only(b"\x80\x03c" + global_name + b".")

    def test_arbitrary_reducer_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsupported reducer"):
            parse_data_only(b"\x80\x03cnumpy\nndarray\n)R.")

    def test_object_array_cannot_contain_numeric_or_executable_samples(self):
        # _reconstruct(ndarray,(0,),b'b'); BUILD(1,(1,),dtype('O8'),False,[123]).
        # Metadata may contain column-name strings only. This never creates a
        # NumPy dtype/array or dispatches its __setstate__ implementation.
        stream = (b"\x80\x03cnumpy.core.multiarray\n_reconstruct\n"
                  b"cnumpy\nndarray\nK\x00\x85C\x01b\x87R("
                  b"K\x01K\x01\x85cnumpy\ndtype\nX\x02\x00\x00\x00O8\x89\x88\x87R"
                  b"(K\x03X\x01\x00\x00\x00|NNNJ\xff\xff\xff\xffJ\xff\xff\xff\xffK?tb"
                  b"\x89]K{atb.")
        with self.assertRaisesRegex(ValueError, "Object sample arrays are forbidden"):
            parse_data_only(stream)

    def test_unknown_opcode_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsupported pickle opcode"):
            parse_data_only(b"\x80\x03\x8f.")  # EMPTY_SET is outside the release vocabulary.


if __name__ == "__main__":
    unittest.main()
