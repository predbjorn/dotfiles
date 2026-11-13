#!/usr/bin/env python3
"""List every Claude Code desktop-app session across all stores.

Reads on-disk session JSON from ~/Library/Application Support/Claude*/claude-code-sessions/
and prints them grouped by project, newest first.

Usage:
    claude-sessions.py              # non-archived sessions, grouped by project
    claude-sessions.py <query>      # filter by title or cwd substring (case-insensitive)
    claude-sessions.py -f           # flat list (no grouping), newest first
    claude-sessions.py -a           # include archived
    claude-sessions.py -w           # work account only
    claude-sessions.py -p           # personal account only
"""
import glob
import json
import os
import sys
from datetime import datetime

STORES = [
    ("work", os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions")),
    ("personal", os.path.expanduser("~/Library/Application Support/Claude-Personal/claude-code-sessions")),
]

ANSI = sys.stdout.isatty()
DIM = "\033[2m" if ANSI else ""
BOLD = "\033[1m" if ANSI else ""
CYAN = "\033[36m" if ANSI else ""
YELLOW = "\033[33m" if ANSI else ""
RESET = "\033[0m" if ANSI else ""


def load_sessions():
    out = []
    for label, root in STORES:
        for path in glob.glob(os.path.join(root, "*", "*", "local_*.json")):
            try:
                with open(path) as f:
                    d = json.load(f)
            except Exception:
                continue
            ts = d.get("lastFocusedAt") or d.get("lastActivityAt") or d.get("createdAt") or 0
            cwd = d.get("cwd") or d.get("originCwd") or "(unknown)"
            out.append({
                "store": label,
                "title": d.get("title") or "(no title)",
                "cwd": cwd,
                "ts": ts,
                "archived": bool(d.get("isArchived")),
                "branch": d.get("branch") or "",
                "id": d.get("sessionId") or os.path.basename(path)[:-5].replace("local_", ""),
                "path": path,
            })
    return out


def project_for(cwd):
    """Collapse worktree paths to the parent project."""
    if "/.claude/worktrees/" in cwd:
        return cwd.split("/.claude/worktrees/")[0]
    if "-wt-" in cwd:
        return cwd.split("-wt-")[0]
    return cwd


def fmt_when(ts):
    if not ts:
        return "        ?       "
    return datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d %H:%M")


def main():
    args = sys.argv[1:]
    flat = False
    include_archived = False
    store_filter = None  # "work" or "personal"
    query = None
    for a in args:
        if a.startswith("-") and len(a) > 1 and all(c in "fawp" for c in a[1:]):
            if "f" in a:
                flat = True
            if "a" in a:
                include_archived = True
            if "w" in a:
                store_filter = "work"
            if "p" in a:
                store_filter = "personal"
        else:
            query = a.lower()

    sessions = load_sessions()
    if not include_archived:
        sessions = [s for s in sessions if not s["archived"]]
    if store_filter:
        sessions = [s for s in sessions if s["store"] == store_filter]
    if query:
        sessions = [s for s in sessions if query in s["title"].lower() or query in s["cwd"].lower()]

    sessions.sort(key=lambda s: s["ts"], reverse=True)

    if flat:
        for s in sessions:
            print(f"{DIM}{fmt_when(s['ts'])}{RESET}  "
                  f"{CYAN}{s['store']:8}{RESET}  "
                  f"{BOLD}{s['title'][:55]:55}{RESET}  "
                  f"{DIM}{s['cwd']}{RESET}")
        print(f"\n{len(sessions)} session(s)")
        return

    by_proj = {}
    for s in sessions:
        by_proj.setdefault(project_for(s["cwd"]), []).append(s)

    projects = sorted(by_proj.keys(), key=lambda p: -max(s["ts"] for s in by_proj[p]))
    for p in projects:
        rows = by_proj[p]
        print(f"\n{YELLOW}{BOLD}{p}{RESET}  {DIM}({len(rows)} sessions){RESET}")
        for s in rows:
            wt = ""
            if s["cwd"] != p:
                wt = f" {DIM}[{s['cwd'].rsplit('/', 1)[-1]}]{RESET}"
            arch = f" {DIM}(archived){RESET}" if s["archived"] else ""
            print(f"  {DIM}{fmt_when(s['ts'])}{RESET}  "
                  f"{CYAN}{s['store']:8}{RESET}  "
                  f"{s['title'][:60]}{wt}{arch}")
    print(f"\n{len(sessions)} session(s) across {len(projects)} projects")


if __name__ == "__main__":
    main()
