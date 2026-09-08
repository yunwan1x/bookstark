#!/usr/bin/env python3
"""Generate BookStark's editable academic templates for the pinned PPTist tree."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


W = 1000
H = 562.5
RECT_PATH = "M 0 0 L 200 0 L 200 200 L 0 200 Z"
CIRCLE_PATH = "M 100 0 A 100 100 0 1 1 99.99 0 Z"
HEX_PATH = "M 50 0 L 150 0 L 200 100 L 150 200 L 50 200 L 0 100 Z"

_counter = 0


def uid(prefix: str) -> str:
    global _counter
    _counter += 1
    return f"bs-{prefix}-{_counter:04d}"


def shape(
    left: float,
    top: float,
    width: float,
    height: float,
    fill: str,
    *,
    path: str = RECT_PATH,
    outline: dict | None = None,
    opacity: float | None = None,
    rotate: float = 0,
    lock: bool = False,
) -> dict:
    item = {
        "type": "shape",
        "id": uid("shape"),
        "left": left,
        "top": top,
        "width": width,
        "height": height,
        "viewBox": [200, 200],
        "path": path,
        "fill": fill,
        "fixedRatio": False,
        "rotate": rotate,
    }
    if outline:
        item["outline"] = outline
    if opacity is not None:
        item["opacity"] = opacity
    if lock:
        item["lock"] = True
    return item


def text(
    value: str,
    left: float,
    top: float,
    width: float,
    height: float,
    *,
    size: float = 20,
    color: str = "#172033",
    weight: int = 400,
    align: str = "left",
    font: str = "Inter",
    text_type: str = "content",
    line_height: float = 1.25,
    italic: bool = False,
    opacity: float | None = None,
) -> dict:
    escaped = (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\n", "<br>")
    )
    style = (
        f"font-size: {size}px; color: {color}; "
        f"font-family: {font}; font-weight: {weight};"
    )
    if italic:
        style += " font-style: italic;"
    item = {
        "type": "text",
        "id": uid("text"),
        "left": left,
        "top": top,
        "width": width,
        "height": height,
        "content": f'<p style="text-align: {align};"><span style="{style}">{escaped}</span></p>',
        "rotate": 0,
        "defaultFontName": font,
        "defaultColor": color,
        "vertical": False,
        "textType": text_type,
        "lineHeight": line_height,
        "inset": [0, 0, 0, 0],
    }
    if opacity is not None:
        item["opacity"] = opacity
    return item


def line(
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    color: str,
    *,
    width: float = 2,
    style: str = "solid",
) -> dict:
    return {
        "type": "line",
        "id": uid("line"),
        "left": x1,
        "top": y1,
        "start": [0, 0],
        "end": [x2 - x1, y2 - y1],
        "points": ["", ""],
        "color": color,
        "style": style,
        "width": width,
    }


def slide(slide_type: str, background: str, elements: list[dict]) -> dict:
    return {
        "id": uid("slide"),
        "elements": elements,
        "background": {"type": "solid", "color": background},
        "type": slide_type,
    }


def quantum_header(number: str, section: str) -> list[dict]:
    return [
        shape(0, 0, W, 8, "#1249BE", lock=True),
        text("QUANTUM BLUE", 44, 28, 220, 18, size=10, color="#1249BE", weight=700),
        text(f"{number} / {section.upper()}", 730, 27, 226, 18, size=10, color="#68748A", weight=600, align="right"),
        line(44, 55, 956, 55, "#D9E4F5", width=1),
    ]


def quantum_footer(page: str) -> list[dict]:
    return [
        text("ACADEMIC RESEARCH REPORT", 44, 530, 260, 16, size=8, color="#748198", weight=600),
        text(page, 900, 530, 56, 16, size=9, color="#1249BE", weight=700, align="right"),
    ]


def quantum_network() -> list[dict]:
    els: list[dict] = []
    points = [
        (690, 54), (770, 26), (850, 54), (930, 26),
        (650, 124), (730, 96), (810, 124), (890, 96), (970, 124),
        (690, 194), (770, 166), (850, 194), (930, 166),
        (650, 264), (730, 236), (810, 264), (890, 236), (970, 264),
        (690, 334), (770, 306), (850, 334), (930, 306),
        (730, 404), (810, 376), (890, 404), (970, 376),
    ]
    for x, y in [(650, 54), (730, 26), (810, 54), (890, 26), (970, 54),
                 (690, 124), (770, 96), (850, 124), (930, 96),
                 (650, 194), (730, 166), (810, 194), (890, 166), (954, 194),
                 (690, 264), (770, 236), (850, 264), (930, 236),
                 (730, 334), (810, 306), (890, 334), (970, 306)]:
        x = min(x, 958)
        y = max(y, 37)
        els.append(shape(x - 42, y - 37, 84, 74, "rgba(255,255,255,0)", path=HEX_PATH,
                         outline={"width": 1, "color": "#D7E7FA", "style": "solid"}))
    edges = [
        (0, 5), (1, 5), (1, 6), (2, 6), (2, 7), (3, 7), (3, 8),
        (4, 5), (5, 6), (5, 9), (5, 10), (6, 7), (6, 10), (6, 11),
        (7, 8), (7, 11), (7, 12), (8, 12), (9, 10), (9, 13), (9, 14),
        (10, 11), (10, 14), (10, 15), (11, 12), (11, 15), (11, 16),
        (12, 16), (13, 14), (14, 15), (14, 18), (14, 19), (15, 16),
        (15, 19), (15, 20), (16, 17), (16, 20), (16, 21), (18, 19),
        (19, 20), (19, 22), (19, 23), (20, 21), (20, 23), (20, 24),
        (21, 25), (22, 23), (23, 24), (24, 25),
    ]
    for a, b in edges:
        els.append(line(*points[a], *points[b], "#AFCFF4", width=1))
    for i, (x, y) in enumerate(points):
        radius = 8 if i in (5, 7, 10, 11, 15, 19, 20, 23) else 4
        els.append(shape(x - radius / 2, y - radius / 2, radius, radius, "#1249BE", path=CIRCLE_PATH))
    return els


def quantum_template() -> dict:
    blue = "#1249BE"
    cyan = "#12B3CE"
    ink = "#152238"
    muted = "#6F7D94"
    pale = "#EFF6FF"
    slides: list[dict] = []

    cover = [
        line(0, 0, 1000, 0, blue, width=4),
        line(0, H - 2, 1000, H - 2, blue, width=2),
        shape(44, 30, 34, 40, "#EAF2FF", path=HEX_PATH,
              outline={"width": 2, "color": blue, "style": "solid"}),
        text("U", 53, 41, 16, 18, size=10, color=blue, weight=800, align="center"),
        text("Department of Engineering\nState University", 88, 31, 260, 42, size=10, color=blue, weight=650, line_height=1.15),
        text("Research Report", 50, 150, 560, 58, size=38, color=blue, weight=760, text_type="title"),
        text("A Novel Quantum Algorithm for\nCombinatorial Optimization", 50, 215, 520, 65, size=22, color=blue, weight=520, text_type="subtitle", line_height=1.18),
        shape(50, 310, 92, 4, cyan),
        text("Author:", 50, 354, 86, 20, size=11, color=blue, weight=800),
        text("Alex Morgan", 136, 354, 210, 20, size=11, color=ink, weight=500),
        text("Supervisor:", 50, 382, 86, 20, size=11, color=blue, weight=800),
        text("Prof. Jane Smith", 136, 382, 230, 20, size=11, color=ink, weight=500),
        text("Date:", 50, 410, 86, 20, size=11, color=blue, weight=800),
        text("May 20, 2026", 136, 410, 230, 20, size=11, color=ink, weight=500),
        *quantum_network(),
        text("1", 930, 514, 30, 18, size=11, color=blue, weight=750, align="right"),
    ]
    slides.append(slide("cover", "#FFFFFF", cover))

    agenda = [
        *quantum_header("01", "Research Roadmap"),
        text("Research Roadmap", 44, 82, 620, 55, size=34, color=ink, weight=720, text_type="title"),
        text("From research question to experimentally validated contribution", 44, 135, 680, 24, size=14, color=muted),
    ]
    items = [
        ("01", "Research Question", "Define the optimization bottleneck and measurable success criteria."),
        ("02", "Methodology", "Design the quantum-classical workflow and evaluation protocol."),
        ("03", "Key Findings", "Compare solution quality, runtime and robustness across baselines."),
        ("04", "Implications", "Translate evidence into reusable scientific and engineering guidance."),
    ]
    for i, (n, title_, desc) in enumerate(items):
        x = 44 + (i % 2) * 462
        y = 195 + (i // 2) * 142
        agenda += [
            shape(x, y, 440, 116, "#FFFFFF", outline={"width": 1, "color": "#D5E3F5", "style": "solid"}),
            shape(x, y, 8, 116, blue if i != 2 else cyan),
            text(n, x + 28, y + 21, 45, 30, size=17, color=blue, weight=750),
            text(title_, x + 80, y + 18, 315, 28, size=19, color=ink, weight=700),
            text(desc, x + 80, y + 54, 320, 46, size=11, color=muted, line_height=1.35),
        ]
    agenda += quantum_footer("02")
    slides.append(slide("contents", "#F7FAFE", agenda))

    framework = [
        *quantum_header("02", "Research Framework"),
        text("Research Framework", 44, 80, 620, 52, size=34, color=ink, weight=720, text_type="title"),
        text("A testable chain from optimization challenge to reproducible evidence", 44, 132, 700, 24, size=14, color=muted),
    ]
    cards = [
        (44, "PROBLEM", "Combinatorial\nsearch space", blue),
        (282, "HYPOTHESIS", "Quantum\nadvantage", cyan),
        (520, "METHOD", "Hybrid variational\nalgorithm", blue),
        (758, "EVIDENCE", "Benchmark &\nablation", cyan),
    ]
    for i, (x, label, title_, color) in enumerate(cards):
        framework += [
            shape(x, 205, 198, 186, "#FFFFFF", outline={"width": 1, "color": "#D8E5F5", "style": "solid"}),
            text(f"0{i + 1}", x + 18, 222, 42, 24, size=12, color=color, weight=750),
            shape(x + 18, 265, 42, 42, "#EBF4FF" if color == blue else "#E9FAFC", path=CIRCLE_PATH),
            text("●", x + 31, 273, 18, 20, size=13, color=color, weight=700, align="center"),
            text(label, x + 18, 323, 160, 18, size=9, color=muted, weight=750),
            text(title_, x + 18, 346, 164, 48, size=16, color=ink, weight=650, line_height=1.2),
        ]
        if i < 3:
            framework += [line(x + 198, 298, x + 238, 298, "#73A9DC", width=2)]
    framework += [
        shape(44, 423, 912, 68, pale),
        text("CORE QUESTION", 66, 440, 130, 18, size=9, color=blue, weight=800),
        text("Can a resource-efficient hybrid quantum model improve solution quality without sacrificing robustness?", 196, 436, 730, 28, size=14, color=ink, weight=550),
        *quantum_footer("03"),
    ]
    slides.append(slide("content", "#FFFFFF", framework))

    method = [
        shape(0, 0, 12, 82, blue),
        text("Methodology", 30, 20, 430, 44, size=30, color=blue, weight=760, text_type="title"),
        text("6", 920, 24, 36, 20, size=12, color=blue, weight=750, align="right"),
        line(30, 72, 956, 72, blue, width=2),
        text("Research Framework", 34, 98, 300, 24, size=14, color=blue, weight=750),
        line(120, 228, 880, 228, "#B8C9DE", width=2),
    ]
    stages = [
        ("P", "Problem\nFormulation", "Define objective\nand constraints"),
        ("A", "Algorithm\nDesign", "Quantum circuit\nconstruction"),
        ("S", "Simulation", "State evolution\nand measurement"),
        ("E", "Evaluation", "Compare with\nbaselines"),
    ]
    for i, (icon, title_, desc) in enumerate(stages):
        x = 120 + i * 253
        method += [
            shape(x - 36, 158, 72, 72, "#FFFFFF", path=CIRCLE_PATH,
                  outline={"width": 2, "color": "#A9C4E7", "style": "solid"}),
            shape(x - 22, 172, 44, 44, "#EFF6FF", path=CIRCLE_PATH),
            text(icon, x - 14, 182, 28, 22, size=14, color=blue, weight=800, align="center"),
            text(title_, x - 78, 254, 156, 52, size=16, color=ink, weight=700, align="center", line_height=1.1),
            text(desc, x - 86, 330, 172, 48, size=10, color="#39475A", align="center", line_height=1.25),
        ]
        if i < 3:
            method.append(text("→", x + 78, 185, 52, 28, size=20, color="#718198", weight=500, align="center"))
    method += [
        shape(30, 433, 926, 78, "#E8F2FF"),
        text("Tools & Data:", 48, 450, 120, 20, size=11, color=blue, weight=800),
        text("Qiskit 1.0, IBM Quantum Simulator; benchmark datasets from QUBO Library (2023).", 48, 476, 820, 20, size=10, color=ink, weight=500),
        text("6", 920, 527, 36, 16, size=9, color=blue, weight=750, align="right"),
    ]
    slides.append(slide("content", "#FFFFFF", method))

    findings = [
        shape(0, 0, 12, 82, blue),
        text("Key Findings", 30, 20, 430, 44, size=30, color=blue, weight=760, text_type="title"),
        text("12", 910, 24, 46, 20, size=12, color=blue, weight=750, align="right"),
        line(30, 72, 956, 72, blue, width=2),
        text("Solution Quality (Higher is Better)", 105, 101, 340, 20, size=10, color=ink, weight=750, align="center"),
        text("Runtime (s)", 650, 101, 240, 20, size=10, color=ink, weight=750, align="center"),
    ]
    categories = ["Max-Cut\n(n=50)", "Graph Coloring\n(n=60)", "TSP\n(n=40)"]
    values = [(175, 125, 78), (171, 132, 91), (152, 113, 71)]
    for i, (proposed, qaoa, anneal) in enumerate(values):
        x = 105 + i * 128
        findings += [
            shape(x, 342 - proposed, 26, proposed, blue),
            shape(x + 32, 342 - qaoa, 26, qaoa, cyan),
            shape(x + 64, 342 - anneal, 26, anneal, "#C4C7CB"),
            text(categories[i], x - 10, 356, 110, 38, size=9, color=ink, align="center", line_height=1.1),
        ]
    findings += [
        line(80, 342, 455, 342, "#68778A", width=1),
        text("Proposed\nAlgorithm", 432, 142, 86, 36, size=8, color=ink, weight=600),
        shape(412, 145, 12, 12, blue),
        text("QAOA", 432, 190, 70, 18, size=8, color=muted),
        shape(412, 192, 12, 12, cyan),
        text("Simulated\nAnnealing", 432, 232, 76, 34, size=8, color=muted),
        shape(412, 236, 12, 12, "#C4C7CB"),
    ]
    graph_left, graph_top, graph_w, graph_h = 580, 130, 350, 212
    for i in range(5):
        findings.append(line(graph_left, graph_top + i * graph_h / 4, graph_left + graph_w, graph_top + i * graph_h / 4, "#E0E7EF", width=1))
    runtime = [
        (blue, [0.94, 0.63, 0.42, 0.2]),
        (cyan, [0.98, 0.79, 0.60, 0.43]),
        ("#8F969D", [0.99, 0.91, 0.81, 0.70]),
    ]
    for color, vals in runtime:
        pts = [(graph_left + i * graph_w / 3, graph_top + value * graph_h) for i, value in enumerate(vals)]
        for point in pts:
            findings.append(shape(point[0] - 4, point[1] - 4, 8, 8, color, path=CIRCLE_PATH))
        for a, b in zip(pts, pts[1:]):
            findings.append(line(*a, *b, color, width=3 if color != "#8F969D" else 2))
    findings += [
        text("n = 20", 559, 358, 90, 18, size=9, color=ink, align="center"),
        text("n = 40", 682, 358, 90, 18, size=9, color=ink, align="center"),
        text("n = 60", 806, 358, 90, 18, size=9, color=ink, align="center"),
        shape(30, 445, 926, 68, "#E8F2FF"),
        text("The proposed algorithm consistently outperforms baselines in solution quality", 50, 462, 810, 18, size=11, color=blue, weight=750),
        text("and shows better scalability.", 50, 484, 620, 18, size=11, color=blue, weight=750),
        text("12", 914, 479, 36, 18, size=10, color=blue, weight=750, align="right"),
    ]
    slides.append(slide("content", "#FFFFFF", findings))

    discussion = [
        *quantum_header("05", "Discussion"),
        text("Discussion & Implications", 44, 80, 660, 52, size=34, color=ink, weight=720, text_type="title"),
        text("What the evidence supports, and where the boundary remains", 44, 132, 680, 24, size=14, color=muted),
    ]
    topics = [
        ("01", "Scientific contribution", "A compact hybrid workflow improves solution quality across heterogeneous benchmark classes."),
        ("02", "Engineering implication", "Performance gains remain useful under practical circuit-depth and sampling constraints."),
        ("03", "Boundary condition", "Benefits narrow as noise and constraint density exceed the calibrated operating range."),
        ("04", "Next experiment", "Validate generalization on larger real-world scheduling and routing instances."),
    ]
    for i, (n, title_, desc) in enumerate(topics):
        x = 44 + (i % 2) * 462
        y = 192 + (i // 2) * 142
        color = blue if i % 2 == 0 else cyan
        discussion += [
            shape(x, y, 440, 118, "#FFFFFF", outline={"width": 1, "color": "#D7E4F4", "style": "solid"}),
            text(n, x + 20, y + 18, 38, 24, size=12, color=color, weight=800),
            text(title_, x + 68, y + 16, 330, 26, size=18, color=ink, weight=700),
            text(desc, x + 68, y + 52, 334, 49, size=11, color=muted, line_height=1.35),
        ]
    discussion += quantum_footer("06")
    slides.append(slide("content", "#F7FAFE", discussion))

    end = [
        shape(0, 0, 14, H, blue, lock=True),
        shape(610, 0, 390, H, "#F4F9FF", lock=True),
        text("CONCLUSION", 48, 74, 220, 20, size=11, color=blue, weight=800),
        text("Evidence before\nadvantage.", 48, 126, 550, 110, size=43, color=ink, weight=760, text_type="title", line_height=1.05),
        text("The strongest result is not a universal claim, but a clearly bounded, reproducible improvement.", 50, 275, 500, 64, size=18, color=muted, weight=450, line_height=1.35),
        shape(48, 375, 470, 73, pale),
        text("NEXT STEP", 67, 392, 108, 17, size=9, color=blue, weight=800),
        text("Scale validation to real-world instances.", 67, 416, 380, 20, size=14, color=ink, weight=650),
        text("THANK YOU  /  QUESTIONS", 48, 505, 320, 18, size=10, color=blue, weight=750),
        *quantum_network(),
    ]
    slides.append(slide("end", "#FFFFFF", end))

    return {
        "title": "Quantum Blue Academic Report",
        "width": W,
        "height": H,
        "theme": {
            "themeColors": [blue, cyan, "#7AA7D8", "#D7E6F7"],
            "fontColor": ink,
            "fontName": "Inter",
            "backgroundColor": "#FFFFFF",
            "shadow": {"h": 0, "v": 3, "blur": 10, "color": "rgba(18, 73, 190, 0.12)"},
            "outline": {"width": 1, "color": "#BFD1E8", "style": "solid"},
        },
        "slides": slides,
    }


def night_header(number: str, section: str) -> list[dict]:
    return [
        shape(0, 0, W, 8, "#21D4D0", lock=True),
        text("DATA NIGHT", 44, 27, 200, 18, size=10, color="#21D4D0", weight=750),
        text(f"{number} / {section.upper()}", 720, 27, 236, 18, size=10, color="#7E8A98", weight=650, align="right"),
        line(44, 55, 956, 55, "#26343F", width=1),
    ]


def night_footer(page: str) -> list[dict]:
    return [
        text("GRAPH INTELLIGENCE LAB", 44, 530, 260, 16, size=8, color="#61717F", weight=650),
        text(page, 900, 530, 56, 16, size=9, color="#21D4D0", weight=750, align="right"),
    ]


def night_texture() -> list[dict]:
    els: list[dict] = []
    for row in range(14):
        for col in range(8):
            x = 675 + col * 31 + (row % 2) * 7
            y = 24 + row * 34
            color = "#21D4D0" if (row * 9 + col) % 11 == 0 else "#2B3843"
            els.append(shape(x, y, 3, 3, color, path=CIRCLE_PATH, opacity=0.85))
    code = [
        "DenseGraphBlock {", "  INPUT road_graph", "  EMBED speed_flow", "  ATTN temporal", "  OUTPUT horizon_12", "}",
    ]
    for i, value in enumerate(code):
        els.append(text(value, 808, 112 + i * 24, 160, 18, size=7, color="#496B73", font="JetBrains Mono"))
    return els


def data_night_template() -> dict:
    bg = "#0B1117"
    panel = "#111A21"
    panel2 = "#151F28"
    cyan = "#21D4D0"
    violet = "#7A5AF8"
    white = "#F3F7FA"
    muted = "#8A98A6"
    slides: list[dict] = []

    cover = [
        line(0, 0, 1000, 0, "#31404B", width=3),
        text("School of Computer Science\nNorthbridge University", 48, 34, 320, 42, size=11, color=cyan, weight=650, line_height=1.16),
        text("Research Report", 48, 145, 560, 60, size=38, color=white, weight=740, text_type="title"),
        text("Scalable Graph Neural Networks\nfor Traffic Flow Prediction", 48, 220, 560, 67, size=22, color=cyan, weight=500, text_type="subtitle", line_height=1.2),
        shape(48, 316, 90, 4, cyan),
        text("Author:", 48, 362, 90, 20, size=11, color=white, weight=800),
        text("Daniel Kim", 138, 362, 230, 20, size=11, color="#C6D0D7", weight=500),
        text("Supervisor:", 48, 391, 90, 20, size=11, color=white, weight=800),
        text("Prof. Laura Chen", 138, 391, 260, 20, size=11, color="#C6D0D7", weight=500),
        text("Date:", 48, 420, 90, 20, size=11, color=white, weight=800),
        text("May 20, 2026", 138, 420, 230, 20, size=11, color="#C6D0D7", weight=500),
        *night_texture(),
        text("1", 930, 514, 30, 18, size=11, color=cyan, weight=750, align="right"),
    ]
    slides.append(slide("cover", bg, cover))

    agenda = [
        *night_header("01", "System Overview"),
        text("Research Roadmap", 44, 82, 630, 52, size=34, color=white, weight=730, text_type="title"),
        text("A compact path from urban graph construction to deployable inference", 44, 134, 740, 24, size=14, color=muted),
    ]
    items = [
        ("01", "Problem Definition", "Urban traffic is dynamic, sparse and spatially interdependent."),
        ("02", "Graph Architecture", "Model multi-scale spatial and temporal dependencies."),
        ("03", "Evaluation", "Measure accuracy, latency and generalization under drift."),
        ("04", "Deployment", "Translate the model into a stable online prediction service."),
    ]
    for i, (n, title_, desc) in enumerate(items):
        x = 44 + (i % 2) * 462
        y = 194 + (i // 2) * 144
        agenda += [
            shape(x, y, 440, 118, panel, outline={"width": 1, "color": "#263642", "style": "solid"}),
            text(n, x + 22, y + 20, 44, 26, size=13, color=cyan if i % 2 == 0 else violet, weight=800),
            text(title_, x + 76, y + 18, 330, 28, size=19, color=white, weight=700),
            text(desc, x + 76, y + 55, 330, 48, size=11, color=muted, line_height=1.35),
        ]
    agenda += night_footer("02")
    slides.append(slide("contents", bg, agenda))

    framework = [
        *night_header("02", "Model Architecture"),
        text("Model Architecture", 44, 80, 620, 52, size=34, color=white, weight=730, text_type="title"),
        text("A multi-scale graph pipeline designed for sparse, drifting mobility signals", 44, 132, 740, 24, size=14, color=muted),
    ]
    stages = [
        ("INPUT", "Road graph\n+ live signals", cyan),
        ("ENCODER", "Spatial graph\nconvolution", violet),
        ("FUSION", "Temporal\nattention", cyan),
        ("OUTPUT", "Multi-horizon\nforecast", violet),
    ]
    for i, (label, title_, color) in enumerate(stages):
        x = 44 + i * 228
        framework += [
            shape(x, 205, 198, 198, panel, outline={"width": 1, "color": "#2B3A45", "style": "solid"}),
            shape(x, 205, 198, 5, color),
            text(label, x + 18, 229, 160, 18, size=9, color=color, weight=800),
            shape(x + 18, 265, 48, 48, "#15262B" if color == cyan else "#201B39", path=CIRCLE_PATH),
            text(str(i + 1), x + 31, 278, 22, 20, size=12, color=color, weight=800, align="center"),
            text(title_, x + 18, 333, 164, 50, size=17, color=white, weight=650, line_height=1.18),
        ]
        if i < 3:
            framework.append(line(x + 198, 304, x + 228, 304, "#3E5964", width=2))
    framework += [
        shape(44, 431, 912, 61, panel2),
        text("DESIGN PRINCIPLE", 63, 448, 150, 18, size=9, color=cyan, weight=800),
        text("Preserve local road topology while learning long-range temporal dependencies.", 218, 444, 700, 25, size=14, color=white, weight=550),
        *night_footer("03"),
    ]
    slides.append(slide("content", bg, framework))

    method = [
        text("Methodology", 28, 22, 420, 42, size=29, color=cyan, weight=740, text_type="title"),
        text("6", 920, 24, 36, 20, size=12, color=cyan, weight=750, align="right"),
        line(28, 70, 956, 70, "#4C6570", width=1),
        text("Overall Framework", 30, 88, 300, 22, size=14, color=cyan, weight=750),
    ]
    stages2 = [
        ("◎", "Graph Construction", "Road network +\nspatial graph"),
        ("✦", "GNN Encoder", "Multi-layer\nmessage passing"),
        ("◉", "Temporal Module", "GRU for temporal\npatterns"),
        ("◇", "Prediction Layer", "Traffic flow\nforecasting"),
    ]
    for i, (icon, title_, desc) in enumerate(stages2):
        x = 30 + i * 235
        color = cyan if i % 2 == 0 else violet
        method += [
            shape(x, 126, 210, 190, panel, outline={"width": 1, "color": violet if i in (1, 2) else "#39525D", "style": "solid"}),
            shape(x + 75, 146, 60, 60, "#10272A" if color == cyan else "#201B37", path=CIRCLE_PATH),
            text(icon, x + 91, 163, 28, 25, size=16, color=color, weight=800, align="center"),
            text(title_, x + 14, 220, 182, 26, size=14, color=white, weight=700, align="center"),
            text(desc, x + 20, 260, 170, 42, size=10, color="#B0BBC4", align="center", line_height=1.25),
            text("→" if i < 3 else "", x + 205, 203, 30, 24, size=16, color=cyan, weight=700, align="center"),
        ]
    method += [
        text("Training Setup", 30, 347, 180, 18, size=11, color=cyan, weight=750),
        shape(30, 374, 442, 116, panel, outline={"width": 1, "color": "#344550", "style": "solid"}),
        text("Optimizer  ·  Adam (lr = 1e-3)\nLoss       ·  MAE\nBatch Size ·  64\nEpochs     ·  100", 48, 391, 390, 85, size=10, color="#C6D0D7", font="JetBrains Mono", line_height=1.35),
        text("Dataset", 522, 347, 150, 18, size=11, color=cyan, weight=750),
        shape(522, 374, 434, 116, panel, outline={"width": 1, "color": "#344550", "style": "solid"}),
        text("METR-LA (207 sensors)\nPEMS-BAY (325 sensors)\nTime range: 2019–2020", 542, 394, 380, 74, size=10, color="#C6D0D7", line_height=1.42),
        text("6", 920, 527, 36, 16, size=9, color=cyan, weight=750, align="right"),
    ]
    slides.append(slide("content", bg, method))

    findings = [
        text("Key Findings", 28, 22, 420, 42, size=29, color=cyan, weight=740, text_type="title"),
        text("12", 910, 24, 46, 20, size=12, color=cyan, weight=750, align="right"),
        line(28, 70, 956, 70, "#4C6570", width=1),
        text("Performance (Lower is Better)", 30, 91, 340, 20, size=11, color=cyan, weight=750),
        text("Predicted vs. Actual (METR-LA)", 554, 91, 350, 20, size=11, color=white, weight=650),
        shape(30, 119, 470, 280, "rgba(255,255,255,0)", outline={"width": 1, "color": "#3D5965", "style": "solid"}),
    ]
    rows = [
        ("Model", "MAE ↓", "RMSE ↓", "MAPE (%) ↓"),
        ("HA", "5.62", "9.15", "17.6"),
        ("ARIMA", "4.35", "7.21", "13.2"),
        ("DCRNN", "3.18", "5.12", "9.6"),
        ("Graph WaveNet", "2.71", "4.36", "8.1"),
        ("Proposed (SCGNN)", "2.28", "3.64", "6.4"),
    ]
    for r, row in enumerate(rows):
        y = 132 + r * 42
        if r == 5:
            findings.append(shape(42, y - 4, 446, 35, "#143138"))
        for c, value in enumerate(row):
            widths = [190, 76, 82, 96]
            lefts = [46, 236, 312, 394]
            findings.append(text(value, lefts[c], y, widths[c], 20, size=9 if r == 0 else 10,
                                 color=cyan if r in (0, 5) else "#C1CBD3",
                                 weight=800 if r in (0, 5) else 500))
        if r < len(rows) - 1:
            findings.append(line(42, y + 30, 488, y + 30, "#2E404A", width=1))
    gx, gy, gw, gh = 548, 120, 408, 278
    for i in range(5):
        findings.append(line(gx, gy + i * gh / 4, gx + gw, gy + i * gh / 4, "#26343E", width=1))
    actual = [0.64, 0.42, 0.53, 0.30, 0.48, 0.26, 0.56, 0.32, 0.44, 0.70, 0.51, 0.78, 0.62]
    predicted = [0.69, 0.47, 0.49, 0.35, 0.43, 0.31, 0.51, 0.37, 0.39, 0.65, 0.56, 0.73, 0.66]
    for color, vals, stroke in [(cyan, actual, 3), (violet, predicted, 2)]:
        pts = [(gx + i * gw / 12, gy + v * gh) for i, v in enumerate(vals)]
        for a, b in zip(pts, pts[1:]):
            findings.append(line(*a, *b, color, width=stroke))
    findings += [
        text("Actual", 820, 126, 68, 16, size=8, color=cyan, weight=700),
        text("Predicted", 892, 126, 64, 16, size=8, color=violet, weight=700),
        text("Time (hours)", 700, 410, 120, 18, size=9, color="#B5C0C8", align="center"),
        shape(28, 454, 928, 58, "#10232A"),
        text("The proposed model achieves the best performance across all metrics.", 48, 472, 820, 20, size=11, color=cyan, weight=650),
        text("12", 916, 474, 34, 18, size=10, color=cyan, weight=750, align="right"),
    ]
    slides.append(slide("content", bg, findings))

    discussion = [
        *night_header("05", "Deployment"),
        text("Deployment Readiness", 44, 80, 650, 52, size=34, color=white, weight=730, text_type="title"),
        text("Operational evidence, limitations and the next validation frontier", 44, 132, 720, 24, size=14, color=muted),
    ]
    topics = [
        ("01", "Accuracy", "Stable gains across peak, off-peak and disruption windows.", cyan),
        ("02", "Latency", "Sub-20 ms inference supports real-time traffic operations.", violet),
        ("03", "Boundary", "Performance degrades under prolonged sensor outages.", cyan),
        ("04", "Next Step", "Add uncertainty calibration and cross-city adaptation.", violet),
    ]
    for i, (n, title_, desc, color) in enumerate(topics):
        x = 44 + (i % 2) * 462
        y = 193 + (i // 2) * 144
        discussion += [
            shape(x, y, 440, 118, panel, outline={"width": 1, "color": "#293945", "style": "solid"}),
            shape(x, y, 5, 118, color),
            text(n, x + 22, y + 19, 42, 24, size=12, color=color, weight=800),
            text(title_, x + 72, y + 17, 330, 26, size=18, color=white, weight=700),
            text(desc, x + 72, y + 55, 330, 44, size=11, color=muted, line_height=1.35),
        ]
    discussion += night_footer("06")
    slides.append(slide("content", bg, discussion))

    end = [
        shape(0, 0, 12, H, cyan, lock=True),
        shape(610, 0, 390, H, "#0E151B", lock=True),
        text("CONCLUSION", 48, 75, 220, 20, size=11, color=cyan, weight=800),
        text("Predict the city.\nRespect the drift.", 48, 126, 540, 112, size=42, color=white, weight=760, text_type="title", line_height=1.06),
        text("A scalable graph model is useful only when accuracy, latency and changing urban context are evaluated together.", 50, 280, 500, 72, size=17, color=muted, line_height=1.38),
        shape(48, 385, 470, 63, panel2),
        text("NEXT", 66, 402, 70, 17, size=9, color=cyan, weight=800),
        text("Cross-city transfer with calibrated uncertainty.", 135, 398, 355, 24, size=13, color=white, weight=600),
        text("THANK YOU  /  QUESTIONS", 48, 505, 320, 18, size=10, color=cyan, weight=750),
        *night_texture(),
        shape(747, 180, 100, 100, "#11252A", path=CIRCLE_PATH,
              outline={"width": 2, "color": cyan, "style": "solid"}),
        text("GNN", 765, 215, 64, 23, size=14, color=white, weight=800, align="center"),
    ]
    slides.append(slide("end", bg, end))

    return {
        "title": "Data Night Academic Report",
        "width": W,
        "height": H,
        "theme": {
            "themeColors": [cyan, violet, "#3D6974", "#263641"],
            "fontColor": white,
            "fontName": "Inter",
            "backgroundColor": bg,
            "shadow": {"h": 0, "v": 4, "blur": 12, "color": "rgba(0, 0, 0, 0.35)"},
            "outline": {"width": 1, "color": "#31424E", "style": "solid"},
        },
        "slides": slides,
    }


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    options = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
    ]
    for option in options:
        if Path(option).exists():
            return ImageFont.truetype(option, size)
    return ImageFont.load_default()


def draw_cover(path: Path, night: bool) -> None:
    scale = 0.64
    width, height = int(W * scale), int(H * scale)
    bg = "#0B1117" if night else "#FFFFFF"
    image = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(image)
    accent = "#21D4D0" if night else "#1249BE"
    ink = "#F3F7FA" if night else "#152238"
    muted = "#8A98A6" if night else "#6F7D94"
    if not night:
        draw.line((0, 0, width, 0), fill=accent, width=3)
        draw.text((30, 20), "Department of Engineering", font=font(8, True), fill=accent)
        draw.text((30, 31), "State University", font=font(8), fill=accent)
    else:
        draw.text((30, 20), "School of Computer Science", font=font(8, True), fill=accent)
        draw.text((30, 31), "Northbridge University", font=font(8), fill=accent)
    draw.text((30, 93), "Research Report", font=font(29, True), fill=ink if night else accent)
    subtitle = "Scalable Graph Neural Networks" if night else "A Novel Quantum Algorithm"
    subtitle2 = "for Traffic Flow Prediction" if night else "for Combinatorial Optimization"
    draw.text((30, 132), subtitle, font=font(12), fill=accent)
    draw.text((30, 151), subtitle2, font=font(12), fill=accent)
    draw.line((30, 199, 84, 199), fill=accent, width=2)
    draw.text((30, 224), "Author:", font=font(7, True), fill=accent if not night else ink)
    draw.text((77, 224), "Alex Morgan" if not night else "Daniel Kim", font=font(7), fill=muted)
    draw.text((30, 240), "Supervisor:", font=font(7, True), fill=accent if not night else ink)
    draw.text((77, 240), "Prof. Jane Smith" if not night else "Prof. Laura Chen", font=font(7), fill=muted)
    draw.text((30, 256), "Date:", font=font(7, True), fill=accent if not night else ink)
    draw.text((77, 256), "May 20, 2026", font=font(7), fill=muted)
    for row in range(9):
        for col in range(7):
            x = 420 + col * 28 + (row % 2) * 7
            y = 18 + row * 28
            c = accent if (row * 6 + col) % 9 == 0 else ("#2B3843" if night else "#B8D8F1")
            draw.ellipse((x, y, x + 4, y + 4), fill=c)
    if night:
        for i, value in enumerate(("Dense Graph Block", "INPUT road_graph", "ATTN temporal", "OUTPUT horizon_12")):
            draw.text((500, 75 + i * 18), value, font=font(6), fill="#496B73")
    else:
        for i in range(6):
            draw.line((410 + i * 32, 80, 500 + i * 20, 245), fill="#C9DDF5", width=1)
    image.save(path, "WEBP", quality=90, method=6)


def register_templates(source_root: Path) -> None:
    store = source_root / "src/store/slides.ts"
    content = store.read_text(encoding="utf-8")
    marker = "      { name: '浅蓝小清新', id: 'template_8', cover: './imgs/template_8.webp', origin: '社区贡献+官方深度完善优化' },"
    insertion = marker + "\n" + "\n".join([
        "      { name: '量子蓝·学术报告', id: 'template_quantum_blue', cover: './imgs/template_quantum_blue.webp', origin: 'BookStark 学术模板' },",
        "      { name: '数据夜·学术报告', id: 'template_data_night', cover: './imgs/template_data_night.webp', origin: 'BookStark 学术模板' },",
    ])
    if "template_quantum_blue" not in content:
        if marker not in content:
            raise RuntimeError("PPTist template registry marker not found")
        store.write_text(content.replace(marker, insertion, 1), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate-pptist-academic-templates.py <pptist-source-root>")
    root = Path(sys.argv[1]).resolve()
    mocks = root / "public/mocks"
    images = root / "public/imgs"
    mocks.mkdir(parents=True, exist_ok=True)
    images.mkdir(parents=True, exist_ok=True)

    register_templates(root)
    (mocks / "template_quantum_blue.json").write_text(
        json.dumps(quantum_template(), ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    (mocks / "template_data_night.json").write_text(
        json.dumps(data_night_template(), ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    draw_cover(images / "template_quantum_blue.webp", night=False)
    draw_cover(images / "template_data_night.webp", night=True)


if __name__ == "__main__":
    main()
