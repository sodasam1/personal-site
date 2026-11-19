import os
import shutil
import subprocess
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
needs_ffmpeg = pytest.mark.skipif(not shutil.which("ffmpeg"), reason="ffmpeg not installed")


@pytest.fixture
def tone(tmp_path):
    """tone(name, seconds, hz, volume_db) -> a stereo 44.1 kHz 16-bit WAV of a sine wave."""
    def make(name="a.wav", seconds=2, hz=440, vol=0):
        p = tmp_path / name
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", f"sine=frequency={hz}:duration={seconds}:sample_rate=44100",
                        "-af", f"volume={vol}dB,pan=stereo|c0=c0|c1=c0", str(p)], check=True)
        return p
    return make
