"""Check text order, ruby rows, and exclusion of vertical text."""

import unittest
from PIL import Image, ImageDraw
from layout import recognize_horizontal


class HorizontalLayoutTests(unittest.TestCase):
    def test_horizontal_rows_keep_annotations_and_skip_vertical_text(self):
        image = Image.new("RGB", (200, 200), "white")
        draw = ImageDraw.Draw(image)
        regions = [(10, 40, 90, 20), (110, 40, 80, 20), (30, 10, 40, 10), (0, 80, 10, 80)]
        for (x, y, w, h), color in zip(regions, ["red", "blue", "purple", "green"]):
            draw.rectangle((x, y, x + w - 1, y + h - 1), fill=color)
        labels = {(255, 0, 0): "hello", (0, 0, 255): "world", (128, 0, 128): "ruby", (0, 128, 0): "vertical"}

        def read(crop):
            return labels[crop.getpixel((crop.width // 2, crop.height // 2))]

        result = recognize_horizontal(image, regions, read)

        self.assertEqual(result.splitlines()[0].strip(), "ruby")
        self.assertEqual(result.splitlines()[1], "hello world")
        self.assertEqual(len(result.splitlines()), 2)


if __name__ == "__main__":
    unittest.main()
