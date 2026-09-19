#!/usr/bin/env python3
"""Print a compact timeline for one session: user prompts + assistant tool calls."""

import glob
import json
import os
import sys

sid = sys.argv[1]
start = sys.argv[2] if len(sys.argv) > 2 else ""
end = sys.argv[3] if len(sys.argv) > 3 else "9"
paths = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}*.jsonl"))
if not paths:
	sys.exit("not found")

for p in paths:
	print("### FILE", p)
	with open(p, errors="replace") as f:
		for line in f:
			try:
				d = json.loads(line)
			except Exception:
				continue
			if d.get("type") not in ("user", "assistant"):
				continue
			ts = (d.get("timestamp") or "")[:19]
			if ts and not (start <= ts <= end):
				continue
			side = "  [sub]" if d.get("isSidechain") else ""
			m = d.get("message", {}) or {}
			c = m.get("content")
			if isinstance(c, str):
				c = [{"type": "text", "text": c}]
			if not isinstance(c, list):
				continue
			for b in c:
				if not isinstance(b, dict):
					continue
				t = b.get("type")
				if t == "text" and b.get("text", "").strip():
					tag = "USER" if d["type"] == "user" else "ASST"
					txt = b["text"].strip().replace("\n", " ⏎ ")
					if tag == "USER" and txt.startswith("<"):
						continue
					print(f"{ts}{side} {tag}: {txt[:600]}")
				elif t == "tool_use":
					i = b.get("input") or {}
					n = b.get("name")
					if n in ("Edit", "Write", "Read", "NotebookEdit"):
						arg = i.get("file_path", "")
						extra = ""
						if n == "Edit":
							extra = f" | old:{str(i.get('old_string', ''))[:60]!r}"
						elif n == "Write":
							extra = f" | {len(str(i.get('content', '')))}b"
						elif n == "Read":
							extra = (
								f" | off={i.get('offset', '')} lim={i.get('limit', '')}"
							)
						print(f"{ts}{side}   {n}: ...{arg[-70:]}{extra}")
					elif n == "Bash":
						print(f"{ts}{side}   Bash: {str(i.get('command', ''))[:160]}")
					elif n in ("Grep", "Glob"):
						print(
							f"{ts}{side}   {n}: {i.get('pattern', '')!r} in {str(i.get('path', ''))[-40:]}"
						)
					elif n == "Skill":
						print(f"{ts}{side}   Skill: {i.get('skill')}")
					elif n == "Agent":
						print(
							f"{ts}{side}   Agent[{i.get('subagent_type')}]: {str(i.get('description', ''))[:80]}"
						)
					elif n == "AskUserQuestion":
						qs = [
							q.get("question", "")[:80]
							for q in (i.get("questions") or [])
						]
						print(f"{ts}{side}   Ask: {qs}")
					else:
						print(f"{ts}{side}   {n}: {str(i)[:110]}")
