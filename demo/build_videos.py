"""Build the finished demo videos from the role recordings.

Each video: a title card, the phone recording framed on the right with a
step heading + caption on the left that changes with each screen, and an
end card. Output is 1920x1080, 30 fps, H.264 + AAC.

Voice-over: put your recording for a video in demo/voiceover/ named after
it (e.g. 01-waiter.m4a / .wav / .mp3), recorded against the silent build so
it starts at 0:00. Re-run this script and it is mixed in. demo/voiceover/
SCRIPT.md has the narration with timecodes.

Usage (from the repo root):  python demo/build_videos.py
Needs ffmpeg/ffprobe on PATH and Pillow.
"""
from __future__ import annotations

import subprocess
import textwrap
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
CLIPS = ROOT / "recordings"
OUT = ROOT / "recordings" / "final"
WORK = OUT / "_work"
VOICE = ROOT / "voiceover"
LOGO = ROOT.parent / "assets" / "logo.png"

W, H, FPS = 1920, 1080, 30
TITLE_SECS, END_SECS, INTRO_SECS = 4.0, 3.5, 5.0
TAIL_HOLD = 3.0  # freeze the last app frame so the final step can be read
WORDS_PER_SEC = 2.6  # comfortable narration pace, used for the script's word budget

# Brand palette (lib/core/theme/app_theme.dart)
CREAM = (251, 249, 244)
GREEN = (6, 122, 55)
BRAND = (8, 168, 76)
DARK = (27, 36, 44)
MUTED = (107, 101, 93)
GREEN_DARK = (4, 74, 34)

FONT_DIR = Path("C:/Windows/Fonts")
F_BOLD = str(FONT_DIR / "segoeuib.ttf")
F_SEMI = str(FONT_DIR / "seguisb.ttf")
F_REG = str(FONT_DIR / "segoeui.ttf")
F_BLACK = str(FONT_DIR / "seguibl.ttf")

# Phone placement (recordings are 1080x2400)
PH_H = 940
PH_W = round(1080 * PH_H / 2400)
PH_X = 1260
PH_Y = (H - PH_H) // 2
BEZEL = 14
RADIUS = 46


@dataclass
class Step:
    at: float
    title: str
    body: str
    say: str = ""


@dataclass
class Clip:
    name: str
    role: str
    heading: str
    tagline: str
    steps: list[Step] = field(default_factory=list)
    title_say: str = ""


CLIPS_SPEC = [
    Clip("01-waiter", "Waiter", "Waiter", "Take orders at the table and send them to the kitchen", [
        Step(0.0, "Sign in with a PIN",
             "Each staff member picks their profile and signs in with a 4-digit PIN.",
             "Every staff member has their own profile. Amit picks his name and signs in with his four-digit PIN."),
        Step(11.9, "Seat the table",
             "Tap a free table and set the number of guests. The waiter is assigned automatically.",
             "He seats the guests at table five."),
        Step(14.4, "Take the order",
             "Add dishes from the menu. Bestsellers and veg / non-veg are marked on every card.",
             "Then he adds dishes from the menu: one Dal Makhani and two Butter Naan."),
        Step(21.1, "Send it to the kitchen",
             "Check the KOT and send it. The kitchen screen gets it straight away.",
             "He checks the kitchen ticket and sends it. The kitchen screen gets it right away."),
        Step(29.4, "Track the order",
             "Order details show every item. Waiters take orders; billing stays with the cashier.",
             "The order is saved. Waiters take orders; billing stays with the cashier."),
        Step(35.1, "Live floor plan",
             "Table T05 now shows as occupied: ₹340, 3 of 4 seats, just now.",
             "Back on the floor plan, table five now shows as occupied."),
    ], title_say="This is Hishobkr for the waiter."),
    Clip("02-kitchen", "Kitchen", "Kitchen", "Cook from a live ticket screen", [
        Step(0.0, "Kitchen sign-in",
             "The chef signs in on the kitchen screen with their own PIN.",
             "The chef signs in on the kitchen screen with his own PIN."),
        Step(8.7, "New tickets arrive",
             "Every KOT shows the table, waiter, time and items, newest first.",
             "New tickets appear instantly."),
        Step(11.7, "Start preparing",
             "One tap moves a ticket to Preparing so everyone knows it's being cooked.",
             "Table five's order is here. One tap, and it moves to Preparing."),
        Step(19.1, "Mark it ready",
             "Marking a ticket ready notifies the waiter on the floor.",
             "When it's cooked, the chef marks it ready, and the waiter is notified on the floor."),
        Step(35.6, "Lock the screen",
             "The kitchen sees tickets only — no bills, payments or reports.",
             "The kitchen sees tickets only. No bills, no payments."),
    ], title_say="Now the kitchen."),
    Clip("03-manager", "Manager", "Manager", "Bills, discounts, cash drawer and staff", [
        Step(0.0, "Manager sign-in",
             "Managers sign in with their PIN and land on the POS.",
             "Neha, the manager, signs in with her PIN."),
        Step(7.1, "Every running order",
             "See the open orders of every table and waiter at a glance.",
             "She sees every running order."),
        Step(9.6, "Open the bill",
             "Table T03: five items, ₹740.",
             "She opens table three's bill: five items, seven hundred and forty rupees."),
        Step(15.7, "Apply a discount",
             "A 10% loyalty discount. Large discounts need a manager's approval.",
             "She gives a ten percent loyalty discount. Bigger discounts need a manager's approval."),
        Step(23.0, "Collect payment",
             "₹1,000 in cash — the ₹334 change is worked out for you.",
             "The customer pays a thousand in cash, and the change is worked out for her."),
        Step(29.0, "Receipt",
             "Invoice INV-1050 from the server, ready to print, WhatsApp or share as PDF.",
             "The receipt has its invoice number from the server, and can be printed, sent on WhatsApp, or shared as a PDF."),
        Step(40.1, "Shift and cash drawer",
             "Expected cash in the drawer updates with every sale: ₹3,532.",
             "The shift dashboard shows how much cash should be in the drawer, updated with every sale."),
        Step(50.0, "Staff management",
             "Change roles, reset PINs or deactivate staff from one list.",
             "In staff management she can change roles, reset PINs, or deactivate staff."),
        Step(59.2, "Sections and tables",
             "Set up floors, tables and seats for the outlet.",
             "And set up the outlet's sections and tables."),
    ], title_say="Next, the manager."),
    Clip("04-cashier-takeaway-upi", "Cashier", "Cashier: takeaway & UPI", "Takeaway orders with add-ons, paid by UPI", [
        Step(0.0, "Cashier sign-in",
             "The cashier signs in and starts a takeaway order.",
             "Rahul, the cashier, starts a takeaway order."),
        Step(6.9, "Customise the dish",
             "Pick the spice level and paid add-ons like Laccha Onions (+₹15).",
             "Paneer Tikka can be customised. He picks medium spicy and adds Laccha Onions for fifteen rupees, then adds Butter Chicken."),
        Step(17.9, "Send the KOT",
             "Two items go to the kitchen in one ticket.",
             "Both dishes go to the kitchen in a single ticket."),
        Step(28.3, "Bill with packaging",
             "The ₹25 takeaway packaging charge is added automatically: ₹670.",
             "For takeaway, the packaging charge is added automatically."),
        Step(34.0, "Pay by UPI",
             "The QR already carries the exact amount and the restaurant's UPI ID.",
             "The customer pays by UPI. The QR already has the exact amount."),
        Step(40.0, "Receipt with add-ons",
             "The bill lists every add-on, so the customer sees why it costs more.",
             "The receipt lists every add-on, so the bill is clear."),
    ], title_say="Now the cashier, with a takeaway order."),
    Clip("05-cashier-cash-in", "Cashier", "Cashier: cash drawer", "Cash in, cash out and every transaction", [
        Step(0.0, "Next order, or check the drawer",
             "After a sale the cashier can start the next order straight away.",
             "After a sale, the cashier can start the next order, or check the cash drawer."),
        Step(8.4, "Shift dashboard",
             "Cash, UPI and card sales for the shift, and the cash expected in the drawer.",
             "The shift dashboard shows every sale."),
        Step(11.3, "Cash in",
             "Record cash added to the drawer, with a reason, for example change top-up.",
             "When cash is added to the drawer, he records it with a reason. Here, five hundred rupees for change."),
        Step(21.6, "Drawer updated",
             "Expected cash goes from ₹2,366 to ₹2,866 straight away.",
             "The expected cash in the drawer updates straight away."),
        Step(26.6, "Find any bill",
             "Search transactions and filter by cash, UPI or card.",
             "And any bill can be found in transactions, filtered by cash, UPI or card."),
    ], title_say="The cashier also looks after the cash drawer."),
    Clip("06-admin", "Owner", "Owner", "Dashboard, reports and settings", [
        Step(0.0, "Owner sign-in",
             "The owner signs in as admin.",
             "Vikram, the owner, signs in as admin."),
        Step(6.5, "Today at a glance",
             "Sales, orders, average bill, cash in drawer and open KOTs.",
             "His home screen shows today's sales, orders, cash in the drawer and open tickets."),
        Step(13.1, "Everything in one place",
             "Shifts, kitchen, transactions, expenses, customers and stock.",
             "Every part of the restaurant is one tap away."),
        Step(18.5, "Reports",
             "Today: 6 orders, ₹2,872. Profit, order types and payment modes.",
             "Reports show today's six orders, the profit, order types and payment modes."),
        Step(25.4, "Best sellers and staff",
             "Top dishes, categories and sales by each staff member.",
             "He sees the best-selling dishes and what each staff member sold, for today, the last seven days, or any dates."),
        Step(41.5, "Settings",
             "Restaurant profile, subscription, GST and charges.",
             "In settings he manages the restaurant profile, subscription and taxes."),
        Step(47.3, "UPI payments",
             "Set the UPI ID once and every bill gets its own payment QR.",
             "And sets the UPI ID once, for every bill."),
    ], title_say="Finally, the owner's view."),
]

INTRO_SAY = "Hishobkr is a restaurant POS for the whole team. Let's follow one day, from the waiter's order to the owner's report."
END_SAY = "Hishobkr. One POS for every role."


# ---------- drawing helpers ----------

def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, width: int) -> list[str]:
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = (line + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def logo(height: int) -> Image.Image:
    im = Image.open(LOGO).convert("RGBA")
    im = im.crop(im.getbbox())
    return im.resize((round(im.width * height / im.height), height), Image.LANCZOS)


def rounded_mask(size, radius) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def background() -> Image.Image:
    """Cream canvas with a soft green glow behind the phone."""
    bg = Image.new("RGB", (W, H), CREAM)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([PH_X - 260, PH_Y - 120, PH_X + PH_W + 260, PH_Y + PH_H + 120],
                                 fill=(*BRAND, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    bg.paste(glow, (0, 0), glow)
    return bg


def base_frame(clip: Clip, index: int, total: int) -> Image.Image:
    """Static parts of the main section: logo, role chip, phone bezel."""
    im = background()
    d = ImageDraw.Draw(im)
    lg = logo(58)
    im.paste(lg, (110, 78), lg)

    chip_f = font(F_SEMI, 26)
    chip = f"{clip.heading}"
    tw = d.textlength(chip, font=chip_f)
    d.rounded_rectangle([110, 190, 110 + tw + 48, 240], 25, fill=GREEN)
    d.text((134, 196), chip, font=chip_f, fill="white")
    d.text((110 + tw + 70, 198), f"Video {index} of {total}", font=font(F_REG, 26), fill=MUTED)

    # phone shadow + bezel
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [PH_X - BEZEL + 10, PH_Y - BEZEL + 24, PH_X + PH_W + BEZEL + 10, PH_Y + PH_H + BEZEL + 24],
        RADIUS + BEZEL, fill=(0, 0, 0, 70))
    sh = sh.filter(ImageFilter.GaussianBlur(28))
    im.paste(sh, (0, 0), sh)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([PH_X - BEZEL, PH_Y - BEZEL, PH_X + PH_W + BEZEL, PH_Y + PH_H + BEZEL],
                        RADIUS + BEZEL, fill=DARK)

    d.text((110, H - 92), "Demo data · Green Candle – Baner Outlet", font=font(F_REG, 24), fill=MUTED)
    return im


def step_layer(step: Step, n: int, total: int) -> Image.Image:
    """Transparent overlay with one step's heading and caption."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x, maxw = 110, 1000
    d.text((x, 330), f"STEP {n} OF {total}", font=font(F_BOLD, 26), fill=BRAND)
    y = 372
    tf = font(F_BOLD, 76)
    for line in wrap(d, step.title, tf, maxw):
        d.text((x, y), line, font=tf, fill=DARK)
        y += 92
    y += 22
    bf = font(F_REG, 40)
    for line in wrap(d, step.body, bf, maxw - 60):
        d.text((x, y), line, font=bf, fill=(68, 64, 58))
        y += 56
    # progress dots
    dy = H - 170
    for i in range(total):
        cx = x + i * 34
        fill = GREEN if i < n else (214, 208, 196)
        d.ellipse([cx, dy, cx + 18, dy + 18], fill=fill)
    return im


def title_card(clip: Clip | None, index: int, total: int) -> Image.Image:
    im = Image.new("RGB", (W, H), GREEN_DARK)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W // 2 - 900, -500, W // 2 + 900, 700], fill=(*BRAND, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    im.paste(glow, (0, 0), glow)
    d = ImageDraw.Draw(im)

    lg = logo(96)
    card_w, card_h = lg.width + 96, lg.height + 64
    cx = (W - card_w) // 2
    d.rounded_rectangle([cx, 170, cx + card_w, 170 + card_h], 36, fill="white")
    im.paste(lg, (cx + 48, 170 + 32), lg)

    def centered(text, fnt, y, fill):
        tw = d.textlength(text, font=fnt)
        d.text(((W - tw) / 2, y), text, font=fnt, fill=fill)

    if clip is None:  # combined intro
        centered("RESTAURANT POS · FULL DEMO", font(F_BOLD, 34), 440, (182, 240, 204))
        centered("From order to owner's report", font(F_BLACK, 104), 500, "white")
        centered("Waiter  ·  Kitchen  ·  Manager  ·  Cashier  ·  Owner", font(F_SEMI, 44), 660, (226, 244, 232))
    else:
        centered(f"HISHOBKR POS DEMO  ·  {index} OF {total}", font(F_BOLD, 34), 440, (182, 240, 204))
        centered(clip.heading, font(F_BLACK, 120), 490, "white")
        centered(clip.tagline, font(F_SEMI, 48), 670, (226, 244, 232))
    centered("Recorded on the live app · sample restaurant data", font(F_REG, 30), H - 120, (160, 210, 180))
    return im


def end_card() -> Image.Image:
    im = Image.new("RGB", (W, H), CREAM)
    d = ImageDraw.Draw(im)
    lg = logo(120)
    im.paste(lg, ((W - lg.width) // 2, 330), lg)

    def centered(text, fnt, y, fill):
        tw = d.textlength(text, font=fnt)
        d.text(((W - tw) / 2, y), text, font=fnt, fill=fill)

    centered("Restaurant POS for every role", font(F_BOLD, 64), 520, DARK)
    centered("Orders · Kitchen · Billing · UPI · Cash drawer · Reports", font(F_REG, 40), 620, MUTED)
    return im


# ---------- video assembly ----------

def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


ENC = ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p",
       "-r", str(FPS), "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-ac", "2"]


def still_segment(png: Path, secs: float, out: Path) -> None:
    """A card held for `secs` with a fade in and out and a silent audio track."""
    run(["ffmpeg", "-v", "error", "-y", "-loop", "1", "-t", f"{secs}", "-i", str(png),
         "-f", "lavfi", "-t", f"{secs}", "-i", "anullsrc=r=48000:cl=stereo",
         "-vf", f"fps={FPS},fade=in:st=0:d=0.5,fade=out:st={secs - 0.5}:d=0.5,format=yuv420p",
         "-shortest", *ENC, str(out)])


def main_segment(clip: Clip, index: int, total: int, out: Path) -> float:
    src = CLIPS / f"{clip.name}.mp4"
    dur = duration(src) + TAIL_HOLD
    base = WORK / f"{clip.name}-base.png"
    base_frame(clip, index, total).save(base)
    mask = WORK / "phone-mask.png"
    rounded_mask((PH_W, PH_H), RADIUS).save(mask)

    inputs = ["-loop", "1", "-t", f"{dur}", "-i", str(base),
              "-i", str(src),
              "-loop", "1", "-t", f"{dur}", "-i", str(mask)]
    graph = [f"[0:v]fps={FPS},format=rgba[bg]",
             f"[1:v]fps={FPS},tpad=stop_mode=clone:stop_duration={TAIL_HOLD},"
             f"scale={PH_W}:{PH_H}:flags=lanczos,format=rgba[ph]",
             "[2:v]format=gray[m]",
             "[ph][m]alphamerge[phr]",
             f"[bg][phr]overlay={PH_X}:{PH_Y}[v0]"]
    last = "v0"
    n = len(clip.steps)
    for i, st in enumerate(clip.steps):
        end = clip.steps[i + 1].at if i + 1 < n else dur
        layer = WORK / f"{clip.name}-step{i + 1}.png"
        step_layer(st, i + 1, n).save(layer)
        k = 3 + i
        inputs += ["-loop", "1", "-t", f"{dur}", "-i", str(layer)]
        fade_out = f",fade=out:st={end - 0.3:.2f}:d=0.3:alpha=1" if i + 1 < n else ""
        graph.append(f"[{k}:v]fps={FPS},format=rgba,fade=in:st={st.at:.2f}:d=0.35:alpha=1{fade_out}[t{i}]")
        graph.append(f"[{last}][t{i}]overlay=0:0:enable='between(t,{st.at:.2f},{end:.2f})'[v{i + 1}]")
        last = f"v{i + 1}"
    graph.append(f"[{last}]format=yuv420p[vout]")
    silence = inputs.count("-i")
    inputs += ["-f", "lavfi", "-t", f"{dur}", "-i", "anullsrc=r=48000:cl=stereo"]
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(graph),
         "-map", "[vout]", "-map", f"{silence}:a", "-t", f"{dur}", *ENC, str(out)])
    return dur


def concat(parts: list[Path], out: Path) -> None:
    lst = WORK / f"{out.stem}-list.txt"
    lst.write_text("".join(f"file '{p.as_posix()}'\n" for p in parts), encoding="utf-8")
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst),
         "-c", "copy", "-movflags", "+faststart", str(out)])


def voice_for(name: str) -> Path | None:
    for ext in (".wav", ".m4a", ".mp3"):
        p = VOICE / f"{name}{ext}"
        if p.exists():
            return p
    return None


def with_voice(video: Path, voice: Path, out: Path) -> None:
    """Lay the narration over the video (narration starts at 0:00)."""
    run(["ffmpeg", "-v", "error", "-y", "-i", str(video), "-i", str(voice),
         "-filter_complex", "[1:a]aresample=48000,loudnorm=I=-16:TP=-1.5:LRA=11,apad[a]",
         "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
         "-shortest", "-movflags", "+faststart", str(out)])


def mmss(t: float) -> str:
    return f"{int(t // 60)}:{t % 60:04.1f}"


def write_script(durations: dict[str, float]) -> None:
    """Narration with timecodes for each finished video (and the full demo)."""
    VOICE.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Voice-over script",
        "",
        "Record one take per video while watching its silent version in",
        "`demo/recordings/final/` (start recording at 0:00). Save it as",
        "`demo/voiceover/<video name>.wav` (or .m4a / .mp3), e.g. `01-waiter.wav`,",
        "then run `python demo/build_videos.py` again to mix it in.",
        "",
        "Each line starts at its timecode; the budget is how many words fit",
        f"before the next line at a relaxed pace (~{WORDS_PER_SEC} words/s). Running a",
        "little long is fine. The full demo (`00-full-demo.mp4`) reuses these takes.",
        "",
        "Full demo only (`00-intro.wav`, over the opening card):",
        f"> {INTRO_SAY}",
        "",
    ]
    for clip in CLIPS_SPEC:
        total = durations[clip.name]
        main_end = total - END_SECS
        lines += [f"## {clip.name}.mp4 — {clip.heading} ({mmss(total)})", "",
                  "| Time | Words | Say |", "|---|---|---|",
                  f"| 0:00.0 | {int(TITLE_SECS * WORDS_PER_SEC)} | {clip.title_say} |"]
        for i, st in enumerate(clip.steps):
            start = TITLE_SECS + st.at
            nxt = TITLE_SECS + clip.steps[i + 1].at if i + 1 < len(clip.steps) else main_end + END_SECS
            budget = max(1, int((nxt - start) * WORDS_PER_SEC))
            lines.append(f"| {mmss(start)} | {budget} | {st.say} |")
        lines += [f"| {mmss(main_end)} | end card | ({END_SAY} — optional) |", ""]
    (VOICE / "SCRIPT.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    total = len(CLIPS_SPEC)

    end_png = WORK / "end.png"
    end_card().save(end_png)
    end_mp4 = WORK / "end.mp4"
    still_segment(end_png, END_SECS, end_mp4)

    intro_png = WORK / "intro.png"
    title_card(None, 0, total).save(intro_png)
    intro_mp4 = WORK / "intro.mp4"
    still_segment(intro_png, INTRO_SECS, intro_mp4)

    bodies = []
    durations: dict[str, float] = {}
    for i, clip in enumerate(CLIPS_SPEC, start=1):
        tpng = WORK / f"{clip.name}-title.png"
        title_card(clip, i, total).save(tpng)
        tmp4 = WORK / f"{clip.name}-title.mp4"
        still_segment(tpng, TITLE_SECS, tmp4)
        mmp4 = WORK / f"{clip.name}-main.mp4"
        main_segment(clip, i, total, mmp4)

        silent = WORK / f"{clip.name}-silent.mp4"
        concat([tmp4, mmp4, end_mp4], silent)
        body = WORK / f"{clip.name}-body.mp4"
        concat([tmp4, mmp4], body)

        final = OUT / f"{clip.name}.mp4"
        voice = voice_for(clip.name)
        if voice:
            with_voice(silent, voice, final)
            narrated = WORK / f"{clip.name}-body-voice.mp4"
            with_voice(body, voice, narrated)
            bodies.append(narrated)
        else:
            silent.replace(final)
            bodies.append(body)
        durations[clip.name] = duration(final)
        print(f"{final.name}: {durations[clip.name]:.1f}s{' with voice-over' if voice else ' (no voice-over yet)'}")

    intro_voice = voice_for("00-intro")
    if intro_voice:
        narrated_intro = WORK / "intro-voice.mp4"
        with_voice(intro_mp4, intro_voice, narrated_intro)
        intro_mp4 = narrated_intro
    full = OUT / "00-full-demo.mp4"
    concat([intro_mp4, *bodies, end_mp4], full)
    write_script(durations)
    print(f"{full.name}: {duration(full):.1f}s")


if __name__ == "__main__":
    main()
