#!/usr/bin/env python3
"""Build a compact index of recent Claude Code sessions."""

import collections
import datetime
import glob
import json
import os
import sys

ROOT = os.path.expanduser("~/.claude/projects")
CUTOFF = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=21)

rows = []
for path in glob.glob(os.path.join(ROOT, "*", "*.jsonl")):
	st = os.stat(path)
	if datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone.utc) < CUTOFF:
		continue
	title = None
	prompts = []
	tools = collections.Counter()
	files_written = collections.Counter()
	ts_first = ts_last = None
	n_assistant = 0
	sidechain = 0
	with open(path, errors="replace") as f:
		for line in f:
			try:
				d = json.loads(line)
			except Exception:
				continue
			t = d.get("type")
			if t == "ai-title":
				title = d.get("aiTitle")
				continue
			ts = d.get("timestamp")
			if ts:
				ts_first = ts_first or ts
				ts_last = ts
			if d.get("isSidechain"):
				sidechain += 1
			if t == "user":
				m = d.get("message", {})
				c = m.get("content")
				if isinstance(c, str):
					txt = c
				elif isinstance(c, list):
					txt = " ".join(
						b.get("text", "")
						for b in c
						if isinstance(b, dict) and b.get("type") == "text"
					)
				else:
					txt = ""
				txt = txt.strip()
				if txt and not txt.startswith("<") and d.get("promptSource") != "hook":
					prompts.append(txt)
			elif t == "assistant":
				n_assistant += 1
				for b in d.get("message", {}).get("content", []) or []:
					if isinstance(b, dict) and b.get("type") == "tool_use":
						name = b.get("name")
						tools[name] += 1
						if name in ("Write", "Edit", "NotebookEdit"):
							fp = (b.get("input") or {}).get("file_path", "?")
							files_written[(name, fp)] += 1
	rows.append(
		{
			"path": path,
			"project": os.path.basename(os.path.dirname(path)),
			"title": title,
			"mtime": datetime.datetime.fromtimestamp(st.st_mtime).strftime(
				"%Y-%m-%d %H:%M"
			),
			"size_kb": st.st_size // 1024,
			"n_prompts": len(prompts),
			"first_prompt": (prompts[0][:220].replace("\n", " ") if prompts else ""),
			"n_assistant": n_assistant,
			"sidechain": sidechain,
			"tools": dict(tools),
			"writes": [
				[k[0], k[1], v] for k, v in files_written.most_common(8) if v > 1
			],
			"total_writes": sum(v for k, v in files_written.items()),
		}
	)

rows.sort(key=lambda r: r["mtime"])
json.dump(rows, open(sys.argv[1], "w"), indent=1)
print(f"{len(rows)} sessions indexed")
