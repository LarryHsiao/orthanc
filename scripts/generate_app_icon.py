"""Draw Orthanc's app icon and write every size macOS and Windows consume.

The tower of Orthanc with the palantir lit at its crown: black stone
silhouetted against an amber sky. No vector file stands behind this script --
it *is* the artwork's source, so any future size is one run away.

    python scripts/generate_app_icon.py

Writes, relative to the repository root:

    macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_<size>.png
    windows/runner/resources/app_icon.ico

Requires Pillow. Nothing else in the tree needs touching: Runner.rc, the
appiconset's Contents.json and installer/orthanc.iss already point at these
exact paths.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Artwork is drawn hard-edged on this canvas and LANCZOS-reduced to each
# output size; the reduction is what supplies the anti-aliasing.
SUPERSAMPLE = 3072

# --- palette: black stone, amber glow ---------------------------------------
FIELD_NEAR = (28, 23, 18)      # #1C1712, the sky warmed by the stone
FIELD_FAR = (10, 10, 12)       # #0A0A0C at the rim
STONE_LIT = (35, 35, 42)       # #23232A
STONE_DARK = (14, 14, 16)      # #0E0E10
RIDGE_LIT = (54, 54, 63)       # the front face, catching the light
RIDGE_DARK = (22, 22, 26)
GLOW_CORE = (255, 233, 176)    # #FFE9B0
GLOW_MID = (245, 165, 36)      # #F5A524

# --- the tower ---------------------------------------------------------------
# Normalised to the art square, y downward, mirrored about x = 0.5. The
# silhouette runs base -> shoulder -> outer horn -> notch -> inner horn ->
# centre valley, then back down the mirrored side.
BASE_Y, BASE_HW = 0.905, 0.185
SHOULDER_Y, SHOULDER_HW = 0.455, 0.108
OUTER_TIP_Y, OUTER_HW = 0.300, 0.130
NOTCH_Y, NOTCH_HW = 0.400, 0.072
INNER_TIP_Y, INNER_HW = 0.335, 0.048
CENTER_NOTCH_Y = 0.398
RIDGE_SQUEEZE = 0.42           # the lit front face, as a fraction of the width

# --- the seeing-stone and its light ------------------------------------------
ORB_CY, ORB_R = 0.248, 0.060
ORB_RIM_BLUR = 0.008
ORB_CORE_BLUR = 0.45           # fraction of the orb's own radius
HALO_R, HALO_FALLOFF, HALO_OPACITY = 0.575, 2.0, 0.90
FIELD_FALLOFF = 1.6
GROUND_HW, GROUND_HH = 0.30, 0.055
GROUND_BLUR, GROUND_OPACITY = 0.035, 0.30

# --- platform shapes ---------------------------------------------------------
APPLE_INSET = 100.0 / 1024.0   # Apple's 824-on-1024 geometry
SUPERELLIPSE_N = 5.0           # the exponent that gives macOS its squircle
SUPERELLIPSE_STEPS = 1440
SHADOW_DROP, SHADOW_BLUR, SHADOW_OPACITY = 0.012, 0.018, 0.42
WINDOWS_CORNER = 0.18          # corner radius as a fraction of the edge

# --- outputs -----------------------------------------------------------------
MACOS_SIZES = (16, 32, 64, 128, 256, 512, 1024)
WINDOWS_SIZES = (16, 24, 32, 48, 64, 128, 256)

# At and below this size the facet line and floor glow only muddy the pixels,
# so the drawing simplifies and the stone grows to hold the eye.
SIMPLE_AT_OR_BELOW = 32
SIMPLE_ORB_SCALE = 1.18
SIMPLE_WIDEN = 1.08

ROOT = Path(__file__).resolve().parent.parent
MACOS_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WINDOWS_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"


def _radial(falloff):
    """A radial ramp on the full canvas: 255 at the centre, 0 at the rim."""
    ramp = Image.radial_gradient("L").resize(
        (SUPERSAMPLE, SUPERSAMPLE), Image.BICUBIC)
    return ramp.point(lambda v: int(255 * max(0.0, 1.0 - v / 255.0) ** falloff))


def _placed_radial(falloff, cy, radius):
    """A radial ramp recentred on (0.5, cy) and reaching 0 at `radius`."""
    k = 0.5 / radius
    return _radial(falloff).transform(
        (SUPERSAMPLE, SUPERSAMPLE), Image.AFFINE,
        (k, 0, 0.5 * SUPERSAMPLE * (1 - k),
         0, k, SUPERSAMPLE * (0.5 - cy * k)),
        Image.BICUBIC, fillcolor=0)


def _vertical(top, bottom):
    """A vertical two-colour ramp filling the canvas."""
    size = (SUPERSAMPLE, SUPERSAMPLE)
    ramp = Image.linear_gradient("L").resize(size, Image.BICUBIC)
    return Image.composite(Image.new("RGB", size, bottom),
                           Image.new("RGB", size, top), ramp)


def _wash(art, colour, mask):
    """Lay `colour` over `art` through a continuous mask."""
    plate = Image.new("RGB", (SUPERSAMPLE, SUPERSAMPLE), colour)
    return Image.composite(plate, art, mask)


def _dim(mask, opacity):
    return mask.point(lambda p: int(p * opacity))


def _tower_polygon(squeeze):
    """The tower silhouette as canvas points, optionally narrowed."""
    half = [(BASE_HW, BASE_Y), (SHOULDER_HW, SHOULDER_Y),
            (OUTER_HW, OUTER_TIP_Y), (NOTCH_HW, NOTCH_Y),
            (INNER_HW, INNER_TIP_Y)]
    points = [(0.5 - hw * squeeze, y) for hw, y in half]
    points.append((0.5, CENTER_NOTCH_Y))
    points += [(0.5 + hw * squeeze, y) for hw, y in reversed(half)]
    return [(x * SUPERSAMPLE, y * SUPERSAMPLE) for x, y in points]


def _filled(draw_shape):
    mask = Image.new("L", (SUPERSAMPLE, SUPERSAMPLE), 0)
    draw_shape(ImageDraw.Draw(mask))
    return mask


def _sky(detail):
    """The field, the halo the stone throws, and the pool at the tower's foot."""
    art = Image.new("RGB", (SUPERSAMPLE, SUPERSAMPLE), FIELD_FAR)
    art = _wash(art, FIELD_NEAR, _radial(FIELD_FALLOFF))
    # The stone must silhouette against a lit sky or it collapses into the
    # field at 16px -- black on near-black reads as a smudge, not a tower.
    halo = _placed_radial(HALO_FALLOFF, ORB_CY, HALO_R)
    art = _wash(art, GLOW_MID, _dim(halo, HALO_OPACITY))
    if not detail:
        return art
    pool = _filled(lambda d: d.ellipse(
        [(0.5 - GROUND_HW) * SUPERSAMPLE, (BASE_Y - GROUND_HH) * SUPERSAMPLE,
         (0.5 + GROUND_HW) * SUPERSAMPLE, (BASE_Y + GROUND_HH) * SUPERSAMPLE],
        fill=255)).filter(ImageFilter.GaussianBlur(SUPERSAMPLE * GROUND_BLUR))
    return _wash(art, GLOW_MID, _dim(pool, GROUND_OPACITY))


def _raise_tower(art, detail):
    """Set the black stone on the field, with its lit front face."""
    widen = 1.0 if detail else SIMPLE_WIDEN
    stone = _filled(lambda d: d.polygon(_tower_polygon(widen), fill=255))
    art = Image.composite(_vertical(STONE_LIT, STONE_DARK), art, stone)
    if not detail:
        return art
    ridge = _filled(lambda d: d.polygon(_tower_polygon(RIDGE_SQUEEZE), fill=255))
    return Image.composite(_vertical(RIDGE_LIT, RIDGE_DARK), art, ridge)


def _set_stone(art, detail):
    """Light the palantir at the crown: a bright core over a hot disc."""
    radius = ORB_R * (1.0 if detail else SIMPLE_ORB_SCALE)
    disc = _filled(lambda d: d.ellipse(
        [(0.5 - radius) * SUPERSAMPLE, (ORB_CY - radius) * SUPERSAMPLE,
         (0.5 + radius) * SUPERSAMPLE, (ORB_CY + radius) * SUPERSAMPLE],
        fill=255))
    rim = disc.filter(ImageFilter.GaussianBlur(SUPERSAMPLE * ORB_RIM_BLUR))
    art = _wash(art, GLOW_MID, rim)
    core = disc.filter(
        ImageFilter.GaussianBlur(SUPERSAMPLE * radius * ORB_CORE_BLUR))
    return _wash(art, GLOW_CORE, core)


def draw_art(detail):
    """The full artwork on an opaque canvas, before any platform shape."""
    return _set_stone(_raise_tower(_sky(detail), detail), detail)


def _squircle_mask(size):
    """Apple's superellipse, walked as a polygon on a `size` square."""
    a = size / 2.0
    points = []
    for step in range(SUPERELLIPSE_STEPS):
        angle = 2.0 * math.pi * step / SUPERELLIPSE_STEPS
        cos_t, sin_t = math.cos(angle), math.sin(angle)
        x = abs(cos_t) ** (2.0 / SUPERELLIPSE_N) * math.copysign(1.0, cos_t)
        y = abs(sin_t) ** (2.0 / SUPERELLIPSE_N) * math.copysign(1.0, sin_t)
        points.append((a + a * x, a + a * y))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def _windows_tile(art):
    """Full-bleed rounded square: Windows applies no mask of its own."""
    tile = art.convert("RGBA")
    corner = int(SUPERSAMPLE * WINDOWS_CORNER)
    tile.putalpha(_filled(lambda d: d.rounded_rectangle(
        [0, 0, SUPERSAMPLE - 1, SUPERSAMPLE - 1], radius=corner, fill=255)))
    return tile


def _macos_tile(art):
    """Apple's squircle, inset on the canvas, over its own drop shadow."""
    body = art.resize((int(SUPERSAMPLE * (1 - 2 * APPLE_INSET)),) * 2,
                      Image.LANCZOS)
    mask = _squircle_mask(body.width)
    offset = int(SUPERSAMPLE * APPLE_INSET)

    shadow = Image.new("L", (SUPERSAMPLE, SUPERSAMPLE), 0)
    shadow.paste(mask, (offset, offset + int(SUPERSAMPLE * SHADOW_DROP)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SUPERSAMPLE * SHADOW_BLUR))

    tile = Image.new("RGBA", (SUPERSAMPLE, SUPERSAMPLE), (0, 0, 0, 0))
    tile.paste(Image.new("RGBA", (SUPERSAMPLE, SUPERSAMPLE), (0, 0, 0, 255)),
               (0, 0), _dim(shadow, SHADOW_OPACITY))
    tile.paste(body.convert("RGBA"), (offset, offset), mask)
    return tile


def _at(tiles, size):
    """The tile of the right detail level, reduced to `size`."""
    detailed = size > SIMPLE_AT_OR_BELOW
    return tiles[detailed].resize((size, size), Image.LANCZOS)


def _write_macos(tiles):
    for size in MACOS_SIZES:
        path = MACOS_DIR / f"app_icon_{size}.png"
        _at(tiles, size).save(path)
        print(f"  {path.relative_to(ROOT)}  {size}x{size}")


def _write_windows(tiles):
    # Pillow matches each requested size against the supplied frames and only
    # thumbnails when none matches, so every frame here is drawn, not scaled.
    frames = [_at(tiles, size) for size in sorted(WINDOWS_SIZES, reverse=True)]
    frames[0].save(WINDOWS_ICO, format="ICO",
                   sizes=[(size, size) for size in WINDOWS_SIZES],
                   append_images=frames[1:])
    listed = ", ".join(str(size) for size in sorted(WINDOWS_SIZES))
    print(f"  {WINDOWS_ICO.relative_to(ROOT)}  [{listed}]")


def main():
    art = {detail: draw_art(detail) for detail in (True, False)}
    print("Orthanc app icon:")
    _write_macos({detail: _macos_tile(a) for detail, a in art.items()})
    _write_windows({detail: _windows_tile(a) for detail, a in art.items()})


if __name__ == "__main__":
    main()
