#!/usr/bin/env python3
"""Print a compact timeline for one session: user prompts + assistant tool calls."""

import glob
import json
import os
import sys

# The session ID prefix used to find matching transcripts.
sid = sys.argv[1]
# The optional earliest timestamp included in the timeline.
start = sys.argv[2] if len(sys.argv) > 2 else ""
# The optional latest timestamp included in the timeline. The default "9" sorts after every timestamp.
end = sys.argv[3] if len(sys.argv) > 3 else "9"
# The transcript paths matching the requested session ID prefix.
paths = glob.glob(os.path.expanduser(f"~/.claude/projects/*/{sid}*.jsonl"))
if not paths:
	sys.exit("not found")

for p in paths:
	print("### FILE", p)
	with open(p, errors="replace") as f:
		for line in f:
			try:
				# The parsed transcript record for this line.
				d = json.loads(line)
			except Exception:
				continue
			if d.get("type") not in ("user", "assistant"):
				continue
			# The event timestamp used for filtering and display.
			ts = (d.get("timestamp") or "")[:19]
			if ts and not (start <= ts <= end):
				continue
			# The label marking a subagent event in the timeline.
			side = "  [sub]" if d.get("isSidechain") else ""
			# The message body carried by this transcript record.
			m = d.get("message", {}) or {}
			# The message text or structured content blocks to display.
			c = m.get("content")
			if isinstance(c, str):
				c = [{"type": "text", "text": c}]
			if not isinstance(c, list):
				continue
			for b in c:
				if not isinstance(b, dict):
					continue
				# The content block type used to choose its timeline format.
				t = b.get("type")
				if t == "text" and b.get("text", "").strip():
					# The role label shown next to message text.
					tag = "USER" if d["type"] == "user" else "ASST"
					# The message text with line breaks flattened for timeline output.
					txt = b["text"].strip().replace("\n", " ⏎ ")
					if tag == "USER" and txt.startswith("<"):
						continue
					print(f"{ts}{side} {tag}: {txt[:600]}")
				elif t == "tool_use":
					# The tool arguments used to describe this call.
					i = b.get("input") or {}
					# The tool name used to choose its timeline format.
					n = b.get("name")
					if n in ("Edit", "Write", "Read", "NotebookEdit"):
						# The affected file path shown for file tool calls.
						arg = i.get("file_path", "")
						# The optional detail shown after a file tool call.
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
						# The question texts, cut to 80 characters, shown for an AskUserQuestion call.
						qs = [
							q.get("question", "")[:80]
							for q in (i.get("questions") or [])
						]
						print(f"{ts}{side}   Ask: {qs}")
					else:
						print(f"{ts}{side}   {n}: {str(i)[:110]}")
