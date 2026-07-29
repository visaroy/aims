#!/usr/bin/env python3
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1200, 675
BG = "#0b1220"
PANEL = "#111a2b"
CARD = "#080d17"
BORDER = "#2a3952"
TEXT = "#e8edf5"
MUTED = "#8ea0b8"
CYAN = "#22d3ee"
GREEN = "#4ade80"
AMBER = "#fbbf24"
PURPLE = "#c084fc"

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT / "docs/assets/aims-handoff-demo.gif"


def font(size, bold=False):
    names = ["DejaVuSansMono-Bold.ttf" if bold else "DejaVuSansMono.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


F_SMALL = font(18)
F_BODY = font(25)
F_BODY_BOLD = font(25, True)
F_TITLE = font(34, True)
F_FINAL = font(48, True)
F_LOGO = font(22, True)

FRAMES = [
    {
        "title": "Human intent, agent workflow",
        "card_label": "HUMAN INTENT",
        "card": '“Move this work to another agent.”',
        "accent": CYAN,
        "bullets": [
            ("Agent understands", "the work must leave this machine safely."),
            ("Agent decides", "ownership must move instead of being shared."),
            ("Agent prepares", "explicit artifacts for the next agent."),
        ],
        "footer": "The human describes the outcome. The agent chooses the AIMS lifecycle.",
    },
    {
        "title": "Agent isolates the task",
        "card_label": "AIMS ACTION",
        "card": "Create a scoped session",
        "accent": PURPLE,
        "bullets": [
            ("Scope", "record the repos, paths, hosts, and services involved."),
            ("Isolation", "create a dedicated branch and worktree."),
            ("Memory", "open metadata, worklog, tests, and summary artifacts."),
        ],
        "footer": "Each agent gets a bounded workspace instead of editing shared state.",
    },
    {
        "title": "Agent proves the checkpoint",
        "card_label": "AIMS ACTION",
        "card": "Save verified progress",
        "accent": GREEN,
        "bullets": [
            ("Verify", "run the task-specific tests and inspect the result."),
            ("Protect", "scan tracked and untracked work for secrets."),
            ("Preserve", "commit the whole worktree and push the exact state."),
        ],
        "footer": "A checkpoint includes evidence, not just a claim that the task is done.",
    },
    {
        "title": "Agent releases ownership",
        "card_label": "AIMS ACTION",
        "card": "Hand off through origin",
        "accent": AMBER,
        "bullets": [
            ("Synchronize", "push the complete session with an exact lease."),
            ("Declare", "mark the session as handed off."),
            ("Stop", "the source agent no longer writes to this session."),
        ],
        "footer": "The agents exchange work through Git, never machine to machine.",
    },
    {
        "title": "Next agent evaluates the handoff",
        "card_label": "AIMS ACTION",
        "card": "Inspect the adoption report",
        "accent": CYAN,
        "bullets": [
            ("Fetch", "read the pushed branch as the source of truth."),
            ("Compare", "show commits and changed paths since handoff."),
            ("Probe", "check that this host has the declared environment."),
        ],
        "footer": "The next agent checks the handoff before it starts changing files.",
    },
    {
        "title": "Next agent continues from artifacts",
        "card_label": "AIMS ACTION",
        "card": "Adopt an isolated worktree",
        "accent": PURPLE,
        "bullets": [
            ("Read", "use commits, metadata, worklog, tests, and the optional brief."),
            ("Do not assume", "private transcripts or hidden reasoning were transferred."),
            ("Continue", "verify the environment, then save new evidence."),
        ],
        "footer": "Any supported agent can continue because the handoff is explicit.",
    },
    {
        "title": "Agent integrates the result",
        "card_label": "AIMS ACTION",
        "card": "Publish the complete session",
        "accent": GREEN,
        "bullets": [
            ("Guard", "refuse dirty, unpushed, or conflicting session state."),
            ("Merge", "integrate the full session diff into main."),
            ("Close", "append the registry entry and remove the session branch."),
        ],
        "footer": "The shared repository records what changed, why, and how it was tested.",
    },
]

DURATIONS = [3500, 4000, 4000, 4000, 4000, 4000, 3500, 3000]


def rounded(draw, box, radius=12, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def render(frame, index):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    rounded(draw, (18, 18, WIDTH - 18, HEIGHT - 18), 18, PANEL, BORDER, 2)
    draw.text((42, 36), "AIMS", font=F_LOGO, fill=CYAN)
    rounded(draw, (130, 31, 290, 66), 12, "#162239", BORDER, 1)
    draw.text((151, 38), "AGENT VIEW", font=F_SMALL, fill=MUTED)
    draw.text((1090, 38), f"{index}/7", font=F_SMALL, fill=MUTED)
    draw.line((42, 82, WIDTH - 42, 82), fill=BORDER, width=1)
    draw.text((42, 108), frame["title"], font=F_TITLE, fill=TEXT)
    draw.text((44, 169), frame["card_label"], font=F_SMALL, fill=frame["accent"])
    rounded(draw, (42, 198, WIDTH - 42, 266), 12, CARD, BORDER, 2)
    draw.rectangle((42, 198, 50, 266), fill=frame["accent"])
    draw.text((75, 217), frame["card"], font=F_BODY_BOLD, fill=TEXT)
    y = 309
    for label, body in frame["bullets"]:
        draw.ellipse((48, y + 10, 58, y + 20), fill=frame["accent"])
        draw.text((76, y), label, font=F_BODY_BOLD, fill=frame["accent"])
        label_width = draw.textbbox((0, 0), label, font=F_BODY_BOLD)[2]
        draw.text((88 + label_width, y), body, font=F_BODY, fill=TEXT)
        y += 72
    draw.line((42, 566, WIDTH - 42, 566), fill=BORDER, width=1)
    draw.text((42, 586), frame["footer"], font=F_SMALL, fill=MUTED)
    progress = int((WIDTH - 84) * index / 7)
    rounded(draw, (42, 630, WIDTH - 42, 642), 6, "#1c2940")
    rounded(draw, (42, 630, 42 + progress, 642), 6, frame["accent"])
    return image


def render_final():
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)
    text = "Give AIMS to your agents"
    box = draw.textbbox((0, 0), text, font=F_FINAL)
    x = (WIDTH - (box[2] - box[0])) // 2
    y = (HEIGHT - (box[3] - box[1])) // 2
    draw.text((x, y), text, font=F_FINAL, fill=TEXT)
    draw.rectangle((x, y + 78, x + 152, y + 84), fill=CYAN)
    return image


def main():
    if len(sys.argv) > 2:
        raise SystemExit("usage: generate-handoff-demo.py [output.gif]")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    frames = [render(frame, i) for i, frame in enumerate(FRAMES, 1)]
    frames.append(render_final())
    frames[0].save(OUTPUT, save_all=True, append_images=frames[1:], duration=DURATIONS, loop=0, optimize=True, disposal=2)
    print(f"Wrote {OUTPUT} ({len(frames)} frames, {sum(DURATIONS)} ms)")


if __name__ == "__main__":
    main()
