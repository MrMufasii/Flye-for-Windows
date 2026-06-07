#!/usr/bin/env python3
"""Generate the validation charts embedded in the top-level README.

Reads docs/ecoli_500kb_metrics.json and writes docs/img/*.png. Pure matplotlib.
"""
import json, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

HERE = os.path.dirname(os.path.abspath(__file__))
IMG = os.path.join(HERE, "img")
os.makedirs(IMG, exist_ok=True)
M = json.load(open(os.path.join(HERE, "ecoli_500kb_metrics.json")))

NAVY, BLUE, TEAL, GREY = "#1b2a4a", "#2f6db5", "#1aa6a6", "#8895a7"
plt.rcParams.update({"font.size": 11, "axes.edgecolor": "#cfd6e0",
                     "axes.grid": True, "grid.color": "#eef1f5",
                     "figure.facecolor": "white", "axes.facecolor": "white"})

contigs = sorted(M["accuracy_vs_reference"]["contigs"], key=lambda c: c["length_bp"], reverse=True)

# --- 1. per-contig identity to reference (zoomed near 100%) -------------------
fig, ax = plt.subplots(figsize=(7.2, 3.6))
names = [c["name"] for c in contigs]
ids = [c["identity_pct"] for c in contigs]
bars = ax.bar(names, ids, color=[BLUE, TEAL, TEAL, TEAL], width=0.6, zorder=3)
ax.set_ylim(99.9, 100.005)
ax.set_ylabel("identity to reference (%)")
ax.set_title("Assembly accuracy vs E. coli K-12 MG1655", fontweight="bold", color=NAVY)
for b, c in zip(bars, contigs):
    ax.text(b.get_x() + b.get_width()/2, b.get_height(), f"{c['identity_pct']:.3f}%",
            ha="center", va="bottom", fontsize=9, color=NAVY)
ax.axhline(100.0, color=GREY, lw=1, ls="--", zorder=2)
fig.text(0.5, -0.02, "aggregate identity 99.999%  -  native Windows, fully static binaries",
         ha="center", fontsize=9, color=GREY)
fig.tight_layout()
fig.savefig(os.path.join(IMG, "accuracy.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

# --- 2. reference reconstruction (contig tiling along the genome) -------------
fig, ax = plt.subplots(figsize=(8.4, 2.8))
colors = [BLUE, TEAL, "#3f86c9", "#16b3a3"]
order = sorted(contigs, key=lambda c: int(c["ref"].split("-")[0]))
for i, c in enumerate(order):
    s, e = (int(x) for x in c["ref"].split("-"))
    ax.add_patch(Rectangle((s, 0.35), e - s, 0.5, facecolor=colors[i % 4],
                           edgecolor="white", zorder=3))
    ax.text((s + e) / 2, 0.6, c["name"].replace("contig_", "c"),
            ha="center", va="center", color="white", fontsize=9, fontweight="bold")
ax.add_patch(Rectangle((0, 0.05), 500000, 0.12, facecolor="#e7ecf3", edgecolor="none"))
ax.text(250000, 0.11, "reference (500 kb region)", ha="center", va="center",
        fontsize=8, color=GREY)
ax.set_xlim(-8000, 508000)
ax.set_ylim(0, 1)
ax.set_yticks([])
ax.set_xlabel("reference position (bp)")
ax.set_title("Reference reconstructed by 4 contigs (contiguous tiling, 584-419,034)",
             fontweight="bold", color=NAVY, fontsize=11)
for spine in ("left", "right", "top"):
    ax.spines[spine].set_visible(False)
fig.tight_layout()
fig.savefig(os.path.join(IMG, "reconstruction.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

# --- 3. assembly summary numbers ---------------------------------------------
a = M["assembly"]
fig, ax = plt.subplots(figsize=(7.2, 3.2))
labels = ["total length", "N50", "largest"]
vals = [a["total_length_bp"], a["n50"], a["largest_bp"]]
bars = ax.barh(labels[::-1], vals[::-1], color=[TEAL, BLUE, NAVY][::-1], height=0.55, zorder=3)
for b, v in zip(bars, vals[::-1]):
    ax.text(b.get_width(), b.get_y() + b.get_height()/2, f"  {v:,} bp",
            va="center", fontsize=10, color=NAVY)
ax.set_xlim(0, max(vals) * 1.25)
ax.set_title(f"Assembly: {a['fragments']} fragments, {a['mean_coverage_x']}x mean coverage, "
             f"{M['runtime_seconds_wall']} s on {M['threads']} threads",
             fontweight="bold", color=NAVY, fontsize=10.5)
ax.set_xlabel("base pairs")
fig.tight_layout()
fig.savefig(os.path.join(IMG, "summary.png"), dpi=150, bbox_inches="tight")
plt.close(fig)

print("wrote:", ", ".join(sorted(os.listdir(IMG))))
