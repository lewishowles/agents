#!/usr/bin/env python3
"""Extract user messages that look like corrections, with preceding assistant context."""

import datetime
import glob
import json
import os
import re
import sys

ROOT = os.path.expanduser("~/.claude/projects")

PAT = re.compile(r"""(?ix)
 \b(
  you\s+(didn't|did\s+not|should\s+have|shouldn't|were\s+asked|just|keep|keeps?|again|already|never)
 |why\s+(did|are|would|is|do)\s+you
 |i\s+(didn't|did\s+not|never)\s+(ask|say|want)
 |i\s+(already|just)\s+(told|said|asked|gave)
 |that's\s+(not|wrong|incorrect)
 |stop\s+(doing|editing|writing|reading|running|re-?)
 |don't\s+(do|edit|write|read|run|rewrite|refactor|add|create)
 |that\s+wasn't\s+(asked|requested|the)
 |out\s+of\s+scope
 |i\s+asked\s+(you\s+)?(for|to)
 |rule\s+(violation|says)
 |against\s+(the\s+)?rules?
 |wasted?\s+(tokens?|time)
 |too\s+(many|much)\s+(tokens?|reads?|edits?|writes?)
 |unnecessar(y|ily)
 |scope\s+creep
 |revert
 |undo\s+that
 |you\s+broke
 |not\s+what\s+i\s+(asked|wanted|said)
 |read\s+the\s+rules?
 |per\s+the\s+rules?
 |the\s+rules?\s+(say|state|require)
 )\b
""")


def matches_correction(text):
	"""Return whether one user message matches the correction vocabulary."""
	return bool(isinstance(text, str) and PAT.search(text))


def main():
	"""Scan recent Claude transcripts and write matching corrections as JSON to the given output path."""
	cutoff = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=21)
	results = []

	for path in glob.glob(os.path.join(ROOT, "*", "*.jsonl")):
		st = os.stat(path)
		if datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone.utc) < cutoff:
			continue
		recs = []
		with open(path, errors="replace") as f:
			for line in f:
				try:
					d = json.loads(line)
				except Exception:
					continue
				if d.get("type") not in ("user", "assistant") or d.get("isSidechain"):
					continue
				m = d.get("message", {})
				c = m.get("content")
				texts, tools = [], []
				if isinstance(c, str):
					texts.append(c)
				elif isinstance(c, list):
					for b in c:
						if not isinstance(b, dict):
							continue
						if b.get("type") == "text":
							texts.append(b.get("text", ""))
						elif b.get("type") == "tool_use":
							i = b.get("input") or {}
							tools.append(
								f"{b.get('name')}({i.get('file_path') or (i.get('command') or i.get('pattern') or i.get('skill') or '')!s:.90})"
							)
				recs.append(
					(
						d.get("type"),
						" ".join(texts).strip(),
						tools,
						d.get("timestamp", ""),
					)
				)

		for idx, (typ, txt, tools, ts) in enumerate(recs):
			if typ != "user" or not txt or txt.startswith("<"):
				continue
			if len(txt) > 4000:
				continue
			if not matches_correction(txt):
				continue
			# gather preceding assistant activity
			prev_tools, prev_text = [], ""
			for j in range(idx - 1, max(-1, idx - 25), -1):
				if recs[j][0] == "user":
					break
				prev_tools = recs[j][2] + prev_tools
				if recs[j][1] and not prev_text:
					prev_text = recs[j][1]
			results.append(
				{
					"session": os.path.basename(path),
					"project": os.path.basename(os.path.dirname(path)),
					"ts": ts,
					"user": txt[:1200],
					"prev_assistant": prev_text[:500],
					"prev_tools": prev_tools[-30:],
				}
			)

	results.sort(key=lambda r: r["ts"])
	json.dump(results, open(sys.argv[1], "w"), indent=1)
	print(f"{len(results)} candidate corrections")


if __name__ == "__main__":
	main()
