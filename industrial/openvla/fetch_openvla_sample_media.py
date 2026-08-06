#!/usr/bin/env python3
#
# This software is in the public domain under CC0 1.0 Universal plus a
# Grant of Patent License.
#
# To the extent possible under law, the author(s) have dedicated all
# copyright and related and neighboring rights to this software to the
# public domain worldwide. This software is distributed without any
# warranty.
#
# You should have received a copy of the CC0 Public Domain Dedication
# along with this software (see the LICENSE.md file). If not, see
# <http://creativecommons.org/publicdomain/zero/1.0/>.
#
"""Fetch official OpenVLA media assets and extract test images for local grounding.

This helper downloads a small set of public demo videos/images from the official
OpenVLA website and generates PNG frames that can be used as sample inputs for
the local /ground endpoint when no real camera captures are available.

Default output layout:

    ./sample-media/
      downloads/
        teaser.png
        openvla--put_blue_cup_on_plate.mp4
        openvla--lift_cheese.mp4
      frames/
        put_blue_cup_on_plate.png
        lift_cheese.png

Dependencies:
  - Python 3.10+
  - pillow
  - imageio
  - imageio-ffmpeg

Example:
    python fetch_openvla_sample_media.py
"""

from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

from PIL import Image

try:
    import imageio
except ImportError as exc:  # pragma: no cover - explicit user guidance
    raise SystemExit(
        "Missing dependency 'imageio'. Install with:\n"
        "  python -m pip install pillow imageio imageio-ffmpeg"
    ) from exc


OPENVLA_SITE = "https://openvla.github.io"
DEFAULT_MEDIA = [
    {
        "name": "put_blue_cup_on_plate",
        "url": f"{OPENVLA_SITE}/static/videos/qualitative_results/good_lang_cond/openvla--put_blue_cup_on_plate.mp4",
        "frame_second": 1.0,
        "prompt": "blue cup",
    },
    {
        "name": "lift_cheese",
        "url": f"{OPENVLA_SITE}/static/videos/qualitative_results/good_lang_cond/openvla--lift_cheese.mp4",
        "frame_second": 1.0,
        "prompt": "cheese",
    },
]
DEFAULT_IMAGE = {
    "name": "openvla_teaser",
    "url": f"{OPENVLA_SITE}/static/images/openvla_teaser.jpg",
}


def download_file(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, destination.open("wb") as output_file:
        output_file.write(response.read())


def extract_frame(video_path: Path, frame_path: Path, frame_second: float) -> None:
    frame_path.parent.mkdir(parents=True, exist_ok=True)
    reader = imageio.get_reader(video_path, format="ffmpeg")
    meta = reader.get_meta_data()
    fps = float(meta.get("fps") or 1.0)
    frame_index = max(0, int(round(frame_second * fps)))
    try:
        frame_array = reader.get_data(frame_index)
    except IndexError:
        frame_count = reader.count_frames()
        frame_array = reader.get_data(max(0, frame_count - 1))
    finally:
        reader.close()
    frame_image = Image.fromarray(frame_array)
    frame_image.save(frame_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        default=Path(__file__).resolve().parent / "sample-media",
        type=Path,
        help="Directory where downloads and extracted frames will be stored.",
    )
    parser.add_argument(
        "--skip-videos",
        action="store_true",
        help="Download only the teaser image and skip the MP4 files / frame extraction.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir: Path = args.output_dir
    downloads_dir = output_dir / "downloads"
    frames_dir = output_dir / "frames"

    teaser_suffix = Path(DEFAULT_IMAGE["url"]).suffix or ".img"
    teaser_path = downloads_dir / f"{DEFAULT_IMAGE['name']}{teaser_suffix}"
    print(f"Downloading {DEFAULT_IMAGE['url']} -> {teaser_path}")
    download_file(DEFAULT_IMAGE["url"], teaser_path)

    if args.skip_videos:
        print("Skipped video downloads and frame extraction.")
        return 0

    for media in DEFAULT_MEDIA:
        video_path = downloads_dir / f"{media['name']}.mp4"
        frame_path = frames_dir / f"{media['name']}.png"
        print(f"Downloading {media['url']} -> {video_path}")
        download_file(media["url"], video_path)
        print(f"Extracting frame at {media['frame_second']}s -> {frame_path}")
        extract_frame(video_path, frame_path, media["frame_second"])
        print(f"Suggested grounding prompt: {media['prompt']}")

    print(f"Sample media ready under {output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
