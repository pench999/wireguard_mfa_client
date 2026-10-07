import argparse
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "windows" / "runner" / "resources"
TRAY_DIR = RESOURCE_DIR / "tray"

CHARCOAL = "#273036"
EMERALD = "#00B978"
AMBER = "#F4AE2B"
RED = "#D84A4A"
MUTED = "#89938F"
HALO = "#F4F7F5"


def _points(scale: int, tray: bool = False):
    def p(items):
        return [(round(x * scale), round(y * scale)) for x, y in items]

    left = p(
        [
            (0.04, 0.06) if tray else (0.19, 0.20),
            (0.43, 0.28) if tray else (0.40, 0.32),
            (0.43, 0.42) if tray else (0.40, 0.44),
            (0.28, 0.34) if tray else (0.31, 0.39),
            (0.28, 0.72) if tray else (0.31, 0.68),
            (0.43, 0.64) if tray else (0.40, 0.63),
            (0.43, 0.78) if tray else (0.40, 0.75),
            (0.04, 0.96) if tray else (0.19, 0.87),
        ]
    )
    right = [(scale - x, y) for x, y in left]
    path = p(
        [(0.34, 0.97), (0.47, 0.58), (0.53, 0.58), (0.66, 0.97)]
        if tray
        else [(0.40, 0.87), (0.48, 0.56), (0.52, 0.56), (0.60, 0.87)]
    )
    return left, right, path


def render(size: int, state: str, tray: bool = False) -> Image.Image:
    oversample = 8
    canvas = size * oversample
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    left, right, path = _points(canvas, tray)

    state_color = {
        "idle": MUTED,
        "authenticating": AMBER,
        "connected": EMERALD,
        "error": RED,
    }[state]

    outline_width = max(round(oversample * 1.25), round(canvas * 0.012))
    draw.polygon(left, fill=HALO, outline=CHARCOAL, width=outline_width)
    draw.polygon(right, fill=HALO, outline=CHARCOAL, width=outline_width)

    if state == "connected":
        draw.polygon(path, fill=EMERALD)

    radius = round(canvas * (0.105 if tray else 0.070))
    center = (canvas // 2, round(canvas * 0.50))
    draw.ellipse(
        (
            center[0] - radius,
            center[1] - radius,
            center[0] + radius,
            center[1] + radius,
        ),
        fill=state_color,
    )

    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_ico(path: Path, state: str, tray: bool = False):
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = [render(size, state, tray) for size in sizes]
    path.parent.mkdir(parents=True, exist_ok=True)
    frames[-1].save(path, format="ICO", append_images=frames[:-1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--android-only', action='store_true')
    args = parser.parse_args()
    if args.android_only:
        save_android_icons()
        return
    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    TRAY_DIR.mkdir(parents=True, exist_ok=True)

    save_ico(RESOURCE_DIR / "app_icon.ico", "connected")
    for state in ("idle", "authenticating", "connected", "error"):
        save_ico(TRAY_DIR / f"tray_{state}.ico", state, tray=True)

    preview = render(512, "connected")
    preview.save(RESOURCE_DIR / "authentication_gate_preview.png")


def save_android_icons():
    resource_dir = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    gate = render(512, 'connected')
    gate = gate.crop(gate.getbbox())
    for density, factor in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
        directory = resource_dir / ('mipmap-' + density)
        directory.mkdir(parents=True, exist_ok=True)
        foreground_size = round(108 * factor)
        foreground = Image.new('RGBA', (foreground_size, foreground_size))
        symbol = gate.copy()
        symbol.thumbnail((round(52 * factor), round(52 * factor)), Image.Resampling.LANCZOS)
        foreground.alpha_composite(symbol, ((foreground_size - symbol.width) // 2, (foreground_size - symbol.height) // 2))
        foreground.save(directory / 'ic_launcher_foreground.png')
        legacy_size = round(48 * factor)
        legacy = Image.new('RGBA', (legacy_size, legacy_size), '#FFFFFF')
        symbol = gate.copy()
        symbol.thumbnail((round(32 * factor), round(32 * factor)), Image.Resampling.LANCZOS)
        legacy.alpha_composite(symbol, ((legacy_size - symbol.width) // 2, (legacy_size - symbol.height) // 2))
        legacy.save(directory / 'ic_launcher.png')


if __name__ == "__main__":
    main()
