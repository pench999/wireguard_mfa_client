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


def _points(scale: int):
    def p(items):
        return [(round(x * scale), round(y * scale)) for x, y in items]

    left = p(
        [
            (0.19, 0.20),
            (0.40, 0.32),
            (0.40, 0.44),
            (0.31, 0.39),
            (0.31, 0.68),
            (0.40, 0.63),
            (0.40, 0.75),
            (0.19, 0.87),
        ]
    )
    right = [(scale - x, y) for x, y in left]
    path = p([(0.40, 0.87), (0.48, 0.56), (0.52, 0.56), (0.60, 0.87)])
    return left, right, path


def render(size: int, state: str, tray: bool = False) -> Image.Image:
    oversample = 8
    canvas = size * oversample
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    left, right, path = _points(canvas)

    state_color = {
        "idle": MUTED,
        "authenticating": AMBER,
        "connected": EMERALD,
        "error": RED,
    }[state]

    if tray:
        outline_width = max(oversample, round(canvas * 0.012))
        draw.line(left + [left[0]], fill=HALO, width=outline_width, joint="curve")
        draw.line(right + [right[0]], fill=HALO, width=outline_width, joint="curve")

    draw.polygon(left, fill=CHARCOAL)
    draw.polygon(right, fill=CHARCOAL)

    if state == "connected":
        draw.polygon(path, fill=EMERALD)

    radius = round(canvas * (0.075 if tray else 0.070))
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
    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    TRAY_DIR.mkdir(parents=True, exist_ok=True)

    save_ico(RESOURCE_DIR / "app_icon.ico", "connected")
    for state in ("idle", "authenticating", "connected", "error"):
        save_ico(TRAY_DIR / f"tray_{state}.ico", state, tray=True)

    preview = render(512, "connected")
    preview.save(RESOURCE_DIR / "authentication_gate_preview.png")


if __name__ == "__main__":
    main()
