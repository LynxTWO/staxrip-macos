"""No disk commands: refuse foreign/duplicate/substituted harness ownership."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("companion_apfs", Path(__file__).with_name("check-companion-apfs-capacity.py"))
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class OwnershipTests(unittest.TestCase):
    def test_foreign_or_missing_image_is_not_adopted(self):
        image = Path("/generated-own-fixture.dmg")
        for info in [{"images": []}, {"images": [{"image-path": "/generated-other-fixture.dmg"}]}]:
            with self.assertRaises(harness.Refused):
                harness.image_entry(info, image)

    def test_duplicate_attachment_refuses_ambiguity(self):
        image = Path("/generated-own-fixture.dmg")
        with self.assertRaises(harness.Refused):
            harness.image_entry({"images": [{"image-path": str(image)}, {"image-path": str(image)}]}, image)

    def test_substituted_owned_image_or_directory_refuses_before_disk_commands(self):
        for replaced in ["image", "root"]:
            with tempfile.TemporaryDirectory(prefix="companion-apfs-guard-") as tmp:
                parent = Path(tmp)
                root = parent / "owned"
                root.mkdir(mode=0o700)
                image = root / "fixture.dmg"
                image.write_bytes(b"generated")
                root_id, image_id = harness.identity(root), harness.identity(image)
                if replaced == "image":
                    image.rename(root / "prior-generated")
                    image.write_bytes(b"replacement")
                else:
                    root.rename(parent / "prior-generated")
                    root.mkdir(mode=0o700)
                    image.write_bytes(b"replacement")
                with patch.object(harness, "tool_plist") as command:
                    with self.assertRaises(harness.Refused):
                        harness.bind_image(root, root_id, image, image_id, root / "mount", None, "generated")
                    command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
