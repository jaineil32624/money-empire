#!/usr/bin/env python3
"""Money Empire — renders the app icon, store graphics, social preview and the
progression infographic from HTML/SVG using headless Chromium.

Uses real in-game screenshots from docs/screenshots/ as backgrounds when present
(generate them first with:  godot --path . -- --tour=docs/screenshots).

Requires: pip install playwright && playwright install chromium
Run:      python3 tools/make_art.py
"""
import base64
import os

from playwright.sync_api import sync_playwright

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MKT = os.path.join(ROOT, "assets", "marketing")
ART = os.path.join(ROOT, "assets", "art")
SHOTS = os.path.join(ROOT, "docs", "screenshots")
os.makedirs(MKT, exist_ok=True)
os.makedirs(ART, exist_ok=True)

GOLD = "#f5c542"
NAVY = "#0b111c"
GREEN = "#2ecc71"
FONT = "'Poppins','Inter','DejaVu Sans',sans-serif"


def shot(name):
    p = os.path.join(SHOTS, name)
    if not os.path.exists(p):
        return ""
    return "data:image/png;base64," + base64.b64encode(open(p, "rb").read()).decode()


COIN = f"""
<svg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'>
  <defs>
    <radialGradient id='cg' cx='0.38' cy='0.32' r='0.75'>
      <stop offset='0' stop-color='#fff3b0'/><stop offset='0.45' stop-color='{GOLD}'/><stop offset='1' stop-color='#b07d00'/>
    </radialGradient>
  </defs>
  <circle cx='100' cy='100' r='92' fill='#7a5600'/>
  <circle cx='100' cy='96' r='90' fill='url(#cg)'/>
  <circle cx='100' cy='96' r='72' fill='none' stroke='#a87700' stroke-width='5' opacity='0.7'/>
  <text x='100' y='128' text-anchor='middle' font-family="{FONT}" font-weight='900' font-size='96' fill='#6b4a00'>$</text>
  <path d='M58 40 l14 18 l14-22 l14 22 l14-22 l14 22 l14-18 l-6 26 h-72z' fill='#fff' opacity='0.9'/>
</svg>"""


def skyline(w, h, color="#132036", seed=7):
    import random
    r = random.Random(seed)
    x = 0
    parts = []
    while x < w:
        bw = r.randint(28, 70)
        bh = r.randint(int(h * 0.25), int(h * 0.95))
        parts.append(f"<rect x='{x}' y='{h-bh}' width='{bw-4}' height='{bh}' fill='{color}'/>")
        for wy in range(h - bh + 10, h - 6, 14):
            for wx in range(x + 6, x + bw - 10, 12):
                if r.random() < 0.45:
                    parts.append(f"<rect x='{wx}' y='{wy}' width='5' height='7' fill='#ffd36e' opacity='{r.uniform(0.35,0.95):.2f}'/>")
        x += bw
    return f"<svg width='{w}' height='{h}' viewBox='0 0 {w} {h}' xmlns='http://www.w3.org/2000/svg'>{''.join(parts)}</svg>"


BASE_CSS = f"""
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:{FONT};background:{NAVY};color:#fff;overflow:hidden}}
.gold{{color:{GOLD}}}
.title{{font-weight:900;letter-spacing:-0.02em;line-height:0.88;color:{GOLD};
  text-shadow:0 6px 0 #6b4a00, 0 12px 40px rgba(0,0,0,.6)}}
.chip{{display:inline-block;padding:8px 16px;border-radius:999px;background:rgba(255,255,255,.08);
  border:1px solid rgba(255,255,255,.18);font-weight:600;margin:0 8px 8px 0}}
"""


def page(w, h, body, css=""):
    return f"<!doctype html><html><head><meta charset='utf-8'><style>{BASE_CSS}{css}</style></head><body style='width:{w}px;height:{h}px'>{body}</body></html>"


def icon(size):
    s = size
    return page(s, s, f"""
<div style='width:{s}px;height:{s}px;border-radius:{int(s*0.22)}px;overflow:hidden;position:relative;
  background:radial-gradient(circle at 50% 30%, #1d3557 0%, #0b111c 70%)'>
  <div style='position:absolute;left:0;right:0;bottom:0;height:{int(s*0.42)}px;opacity:.9'>{skyline(s, int(s*0.42), '#16243d', 3)}</div>
  <div style='position:absolute;left:{int(s*0.16)}px;top:{int(s*0.1)}px;width:{int(s*0.68)}px;height:{int(s*0.68)}px'>{COIN}</div>
  <div style='position:absolute;left:0;right:0;bottom:{int(s*0.07)}px;text-align:center;font-weight:900;
    font-size:{int(s*0.105)}px;color:#fff;letter-spacing:.06em;text-shadow:0 3px 8px #000'>EMPIRE</div>
</div>""")


def hero(w, h, bg, title_size, tagline_size, chips=True, chip_size=18):
    img = f"<img src='{bg}' style='position:absolute;inset:0;width:100%;height:100%;object-fit:cover'>" if bg else ""
    chip_html = ""
    if chips:
        chip_html = "<div style='margin-top:18px;font-size:%dpx'>" % chip_size + "".join(
            f"<span class='chip'>{c}</span>" for c in ["Jobs &rarr; Businesses", "Real estate", "Live stock market", "Booms &amp; crashes", "100-player online", "Mansions &amp; hypercars"]) + "</div>"
    return page(w, h, f"""
<div style='position:relative;width:{w}px;height:{h}px;overflow:hidden'>
  {img}
  <div style='position:absolute;inset:0;background:linear-gradient(90deg, rgba(11,17,28,.97) 0%, rgba(11,17,28,.86) 42%, rgba(11,17,28,.15) 75%, rgba(11,17,28,0) 100%)'></div>
  <div style='position:absolute;left:{int(w*0.05)}px;top:50%;transform:translateY(-50%);max-width:{int(w*0.6)}px'>
    <div style='font-weight:800;color:{GREEN};font-size:{int(tagline_size*0.85)}px;letter-spacing:.12em'>START BROKE. DIE RICH.</div>
    <div class='title' style='font-size:{title_size}px;margin:8px 0 14px'>MONEY<br>EMPIRE</div>
    <div style='font-size:{tagline_size}px;font-weight:500;line-height:1.35;opacity:.95'>Homeless with <b class='gold'>$100</b>. Race everyone to <b class='gold'>$1&nbsp;BILLION</b>.</div>
    {chip_html}
  </div>
  <div style='position:absolute;right:{int(w*0.04)}px;bottom:{int(h*0.06)}px;width:{int(h*0.32)}px;height:{int(h*0.32)}px;filter:drop-shadow(0 10px 20px rgba(0,0,0,.6))'>{COIN}</div>
</div>""")


def infographic():
    steps = [
        ("01", "HUSTLE", "Deliver packages, wash cars, mow lawns, food runs, warehouse &amp; dock shifts.", "$100 &rarr; $1K", "#2ecc71"),
        ("02", "OWN", "Taco stands to gas stations. Upgrade, hire workers, earn every hour.", "$1K &rarr; $1M", "#f5c542"),
        ("03", "EXPAND", "Flip houses, rent out penthouses, buy factories, hotels and shipping lines.", "$1M &rarr; $100M", "#4f8cff"),
        ("04", "DOMINATE", "Malls, banks, mega-corps, space. Time the market through booms and crashes.", "$100M &rarr; $1B", "#b388ff"),
        ("05", "LEGACY", "Build your skyscraper, launch a rocket, buy an island. Race to $1 TRILLION.", "$1B &rarr; $1T", "#ff6fb5"),
    ]
    cards = "".join(f"""
<div style='flex:1;background:#131c2e;border:1px solid #2a3a5c;border-top:6px solid {c};border-radius:18px;padding:22px 20px;position:relative'>
  <div style='font-size:15px;font-weight:800;color:{c};letter-spacing:.1em'>{n}</div>
  <div style='font-size:30px;font-weight:900;margin:4px 0 10px'>{t}</div>
  <div style='font-size:17px;line-height:1.45;color:#c9d2e3'>{d}</div>
  <div style='margin-top:16px;font-size:20px;font-weight:800;color:{c}'>{m}</div>
</div>""" for n, t, d, m, c in steps)
    return page(1600, 520, f"""
<div style='padding:40px 46px'>
  <div style='display:flex;align-items:baseline;gap:18px;margin-bottom:26px'>
    <div style='font-size:40px;font-weight:900' class='gold'>The road to a billion</div>
    <div style='font-size:20px;color:#8a96ab'>one city · five districts · a living economy that booms and crashes</div>
  </div>
  <div style='display:flex;gap:18px'>{cards}</div>
</div>""")


def render(pg, html, w, h, out):
    pg.set_viewport_size({"width": w, "height": h})
    pg.set_content(html)
    pg.wait_for_timeout(150)
    pg.screenshot(path=out, omit_background=True, clip={"x": 0, "y": 0, "width": w, "height": h})
    print("wrote", os.path.relpath(out, ROOT))


def main():
    bg = shot("04_hypercar.png") or shot("01_title.png")
    bg2 = shot("06_night_heli.png") or bg
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page()
        render(pg, icon(512), 512, 512, os.path.join(MKT, "app_icon_512.png"))
        render(pg, icon(1024), 1024, 1024, os.path.join(MKT, "app_icon_1024.png"))
        render(pg, icon(192), 192, 192, os.path.join(MKT, "app_icon_192.png"))
        render(pg, hero(1280, 640, bg, 120, 30), 1280, 640, os.path.join(MKT, "github_social_preview.png"))
        render(pg, hero(1024, 500, bg2, 96, 24, True, 15), 1024, 500, os.path.join(MKT, "play_store_feature_graphic.png"))
        render(pg, hero(920, 430, bg, 92, 22, False), 920, 430, os.path.join(MKT, "steam_header_capsule.png"))
        render(pg, hero(1920, 640, bg, 150, 36), 1920, 640, os.path.join(ART, "banner_wide.png"))
        render(pg, infographic(), 1600, 520, os.path.join(ART, "progression.png"))
        b.close()


if __name__ == "__main__":
    main()
