from conftest import needs_ffmpeg
from kitaudio import extras, media

pytestmark = needs_ffmpeg


def test_peaks_and_duration(tone):
    ok, dur, peaks, err = media.analyze_audio("ffmpeg", tone(seconds=2))
    assert ok, err
    assert abs(dur - 2) < 0.1 and 0 < len(peaks) <= 200 and max(peaks) == 255


def test_loudness_orders_by_volume(tone):
    ok1, quiet, _ = extras.measure_loudness("ffmpeg", tone("q.wav", 3, 440, -20))
    ok2, loud, _ = extras.measure_loudness("ffmpeg", tone("l.wav", 3, 440, -6))
    assert ok1 and ok2 and loud - quiet > 10 and -60 < quiet < 0


def test_probe(tone):
    ok, info, err = extras.probe_audio("ffprobe", tone(seconds=1))
    assert ok, err
    assert info["sample_rate"] == 44100 and info["channels"] == 2 and abs(info["duration_s"] - 1) < 0.1


def test_slice_makes_the_requested_length_and_bit_depth(tone, tmp_path):
    src = tone(seconds=4)
    out = tmp_path / "s.wav"
    ok, err = extras.slice_wav("ffmpeg", src, out, 1.0, 2.5, bits=24)
    assert ok, err
    ok, info, _ = extras.probe_audio("ffprobe", out)
    assert ok and abs(info["duration_s"] - 1.5) < 0.05 and info["codec"] == "pcm_s24le"


def test_bad_inputs_are_refused_without_running_anything(tmp_path):
    assert extras.slice_wav("ffmpeg", tmp_path / "x.wav", tmp_path / "y.wav", 5, 1)[0] is False
    assert extras.slice_wav("ffmpeg", tmp_path / "x.wav", tmp_path / "y.wav", 0, 9999)[0] is False
    assert extras.slice_wav("ffmpeg", tmp_path / "x.txt", tmp_path / "y.wav", 0, 1) == (False, "unsupported file type")
    assert extras.measure_loudness("ffmpeg", tmp_path / "x.txt")[0] is False
