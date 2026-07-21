from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "threaded-timeline-optical-sizes"
OUT.mkdir(parents=True, exist_ok=True)

FONT = "/System/Library/Fonts/Helvetica.ttc"

VARIANTS = {
    "large": {
        "label": "B-Large",
        "gap": 0.15,
        "thread": 0.18,
        "radius": 0.09,
        "note": "Dense mass; strongest large-size icon silhouette",
    },
    "medium": {
        "label": "B-Medium",
        "gap": 0.21,
        "thread": 0.22,
        "radius": 0.12,
        "note": "Moderate optical opening and stronger Thread",
    },
    "small": {
        "label": "B-Small",
        "gap": 0.28,
        "thread": 0.28,
        "radius": 0.16,
        "note": "Pixel-conscious gaps and Thread for tiny contexts",
    },
}

SIZES = (1024, 128, 64, 32, 24)


def dimensions(size: int, spec: dict[str, float]) -> dict[str, int]:
    # B keeps a 2.6:1 card ratio at every optical size. The mark is centered,
    # while gaps, Thread width, and corner radius receive optical correction.
    card_h = max(5, round(size * 220 / 1024))
    card_w = max(13, round(card_h * 2.6))
    gap = max(1, round(card_h * spec["gap"]))
    radius = max(1, round(card_h * spec["radius"]))
    thread_w = max(1, round(card_h * spec["thread"]))

    total_h = card_h * 3 + gap * 2
    x = round((size - card_w) / 2)
    y = round((size - total_h) / 2)
    thread_x = round(x + card_w * 0.25 - thread_w / 2)
    extension = max(1, round(card_h * 0.24))

    return {
        "card_h": card_h,
        "card_w": card_w,
        "gap": gap,
        "radius": radius,
        "thread_w": thread_w,
        "x": x,
        "y": y,
        "thread_x": thread_x,
        "extension": extension,
    }


def draw_mark(size: int, spec: dict[str, float], supersample: int = 8) -> Image.Image:
    d = dimensions(size, spec)
    scale = supersample
    canvas = Image.new("RGB", (size * scale, size * scale), "white")
    draw = ImageDraw.Draw(canvas)

    def sc(value: int) -> int:
        return value * scale

    x = d["x"]
    y = d["y"]
    card_w = d["card_w"]
    card_h = d["card_h"]
    gap = d["gap"]
    radius = d["radius"]
    thread_x = d["thread_x"]
    thread_w = d["thread_w"]
    extension = d["extension"]

    # The black rear segment stays straight through the entire itinerary.
    draw.rounded_rectangle(
        (
            sc(thread_x),
            sc(y - extension),
            sc(thread_x + thread_w),
            sc(y + card_h * 3 + gap * 2 + extension),
        ),
        radius=sc(max(1, thread_w // 2)),
        fill="black",
    )

    card_ys = [y, y + card_h + gap, y + (card_h + gap) * 2]
    for card_y in card_ys:
        draw.rounded_rectangle(
            (sc(x), sc(card_y), sc(x + card_w), sc(card_y + card_h)),
            radius=sc(radius),
            fill="black",
        )

    # The Thread is in front of the outer cards and behind the middle card.
    # White is a monochrome construction convention for the foreground pass.
    for card_y in (card_ys[0], card_ys[2]):
        draw.rectangle(
            (
                sc(thread_x),
                sc(card_y),
                sc(thread_x + thread_w),
                sc(card_y + card_h),
            ),
            fill="white",
        )

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    index = 1 if bold else 0
    return ImageFont.truetype(FONT, size=size, index=index)


def make_study_sheet() -> Path:
    sheet = Image.new("RGB", (2400, 1800), "white")
    draw = ImageDraw.Draw(sheet)
    draw.text((90, 58), "Threaded Timeline — B optical-size study", font=font(44, True), fill="#111")
    draw.text(
        (90, 116),
        "Same 2.6:1 cards and 25% Thread position; only gap, Thread width, and radius receive optical correction.",
        font=font(22),
        fill="#444",
    )
    draw.line((90, 160, 2310, 160), fill="#d5d5d5", width=2)

    panel_w = 700
    panel_h = 1510
    panel_y = 210
    panel_xs = (90, 850, 1610)

    for panel_x, (key, spec) in zip(panel_xs, VARIANTS.items()):
        draw.rounded_rectangle(
            (panel_x, panel_y, panel_x + panel_w, panel_y + panel_h),
            radius=28,
            fill="#fafafa",
            outline="#dedede",
            width=2,
        )
        draw.text((panel_x + 34, panel_y + 28), spec["label"], font=font(34, True), fill="#111")
        draw.text(
            (panel_x + 34, panel_y + 78),
            f'gap {int(spec["gap"] * 100)}%  ·  Thread {int(spec["thread"] * 100)}%  ·  radius {int(spec["radius"] * 100)}%',
            font=font(20),
            fill="#444",
        )
        draw.text((panel_x + 34, panel_y + 112), spec["note"], font=font(18), fill="#666")

        master = draw_mark(1024, spec).resize((430, 430), Image.Resampling.LANCZOS)
        sheet.paste(master, (panel_x + 135, panel_y + 160))
        draw.text((panel_x + 34, panel_y + 620), "Normalized preview", font=font(18, True), fill="#444")

        draw.line(
            (panel_x + 34, panel_y + 660, panel_x + panel_w - 34, panel_y + 660),
            fill="#dedede",
            width=2,
        )
        draw.text((panel_x + 34, panel_y + 690), "Native-size raster outputs", font=font(22, True), fill="#222")

        native_y = panel_y + 750
        native_x = panel_x + 34
        for target in (128, 64, 32, 24):
            icon = draw_mark(target, spec)
            sheet.paste(icon, (native_x, native_y), icon if icon.mode == "RGBA" else None)
            d = dimensions(target, spec)
            draw.text(
                (native_x, native_y + target + 10),
                f'{target}px\nT {d["thread_w"]}px · gap {d["gap"]}px',
                font=font(16),
                fill="#555",
                spacing=3,
            )
            native_x += target + 58

        draw.text((panel_x + 34, panel_y + 1010), "Pixel inspection — nearest-neighbor enlargement", font=font(22, True), fill="#222")
        zoom_y = panel_y + 1060
        zoom_x = panel_x + 34
        for target, factor in ((32, 7), (24, 8)):
            icon = draw_mark(target, spec)
            zoomed = icon.resize((target * factor, target * factor), Image.Resampling.NEAREST)
            sheet.paste(zoomed, (zoom_x, zoom_y))
            draw.text(
                (zoom_x, zoom_y + zoomed.height + 10),
                f"{target}px ×{factor}",
                font=font(17),
                fill="#555",
            )
            zoom_x += zoomed.width + 55

    out = OUT / "threaded-timeline-b-optical-size-study.png"
    sheet.save(out, optimize=True)
    return out


def main() -> None:
    for key, spec in VARIANTS.items():
        for size in SIZES:
            draw_mark(size, spec).save(OUT / f"b-{key}-{size}.png", optimize=True)
    print(make_study_sheet())


if __name__ == "__main__":
    main()
