/** The pieces a reply splits into: prose for Claude Code's Markdown, and tables and the closing Over to you quote for the skin to draw. */
export type ReplySegment =
	| { kind: "prose"; text: string }
	| { kind: "table"; rows: string[][]; widths: number[] }
	| { kind: "card"; text: string };

/** Visible text and its inline Markdown style in a table cell. */
export type CellSpan = { text: string; bold: boolean; code: boolean };

/** One drawn row of a table: a border line, or one line of wrapped cell text. */
export type TableLine =
	| { kind: "border"; text: string }
	| { kind: "cells"; cells: CellSpan[][]; header: boolean };

/** The bold "Over to you:" or "Over to you" label that opens the closing quote. */
const OVER_TO_YOU_LABEL = /^\*\*Over to you(?::\*\*|\*\*)/;
/**
 * Characters most terminals draw two cells wide (East Asian scripts and emoji), which would push table borders out of line.
 * The emoji range also matches some narrow symbols such as © and ™, so tables holding those keep Claude Code's drawing too.
 */
const WIDE_CHARACTER = /[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE10-\uFE6F\uFF01-\uFF60\uFFE0-\uFFE6\u{20000}-\u{3FFFD}]|\p{Extended_Pictographic}/u;

/**
 * Split a reply into prose, tables and a final Over to you quote, so the skin
 * can draw the tables and the quote itself.
 *
 * The card segment holds the quote's contents without the quote markers or
 * the label. Returns null when the reply has neither, or when any table cannot
 * be boxed, so that Claude Code draws the whole reply as usual. Tables inside
 * code fences are left as prose.
 *
 * @param  {string}  text
 *     The reply's Markdown.
 * @param  {number}  columns
 *     The width the reply is drawn into, in character cells.
 */
export function replySegments(text: string, columns: number): ReplySegment[] | null {
	const lines = text.split("\n");
	let cardStart = lines.length;
	let quoteSeen = false;

	for (let index = lines.length - 1; index >= 0; index--) {
		if (/^\s*$/.test(lines[index])) {
			if (quoteSeen) {
				break;
			}

			continue;
		}

		if (!/^>\s?/.test(lines[index])) {
			break;
		}

		quoteSeen = true;
		cardStart = index;
	}

	const quoted = lines.slice(cardStart).map(line => line.replace(/^>\s?/, ""));
	const card = cardStart < lines.length && OVER_TO_YOU_LABEL.test(quoted[0])
		? [quoted[0].replace(OVER_TO_YOU_LABEL, ""), ...quoted.slice(1)].join("\n").trim()
		: null;
	const body = card === null ? lines : lines.slice(0, cardStart);
	const segments: ReplySegment[] = [];
	let proseStart = 0;
	let fence: { character: string; length: number } | null = null;
	/** Add a run of reply lines as prose, without blank lines at either end, so pieces stay one blank line apart. */
	const addProse = (start: number, end: number) => {
		const prose = body.slice(start, end);

		while (prose.length > 0 && /^\s*$/.test(prose[0])) {
			prose.shift();
		}

		while (prose.length > 0 && /^\s*$/.test(prose.at(-1) ?? "")) {
			prose.pop();
		}

		if (prose.length > 0) {
			segments.push({ kind: "prose", text: prose.join("\n") });
		}
	};

	for (let index = 0; index < body.length - 1; index++) {
		const marker = body[index].match(/^ {0,3}(`{3,}|~{3,})(.*)$/);

		if (marker) {
			if (fence === null) {
				fence = { character: marker[1][0], length: marker[1].length };
			} else if (marker[1][0] === fence.character && marker[1].length >= fence.length && /^\s*$/.test(marker[2])) {
				fence = null;
			}

			continue;
		}

		if (fence !== null) {
			continue;
		}

		const header = cells(body[index]);
		const divider = cells(body[index + 1]);

		if (!header || !divider || header.length !== divider.length ||
			!divider.every(cell => /^:?-{3,}:?$/.test(cell))) {
			continue;
		}

		const rows = [header];
		let end = index + 2;

		while (end < body.length) {
			const row = cells(body[end]);

			if (!row) {
				break;
			}

			rows.push(Array.from({ length: header.length }, (_, column) => row[column] ?? ""));
			end++;
		}

		const widths = tableWidths(rows, columns);

		if (widths === null) {
			return null;
		}

		addProse(proseStart, index);
		segments.push({ kind: "table", rows, widths });
		proseStart = end;
		index = end - 1;
	}

	addProse(proseStart, body.length);

	if (card !== null) {
		segments.push({ kind: "card", text: card });
	}

	return segments.some(segment => segment.kind !== "prose") ? segments : null;
}

/**
 * Lay out one table as rounded border lines and rows of padded cells. A cell
 * that is wider than its column wraps onto extra lines.
 *
 * @param  {string[][]}  rows
 *     The table's cells, header row first, still holding their inline Markdown.
 * @param  {number[]}  widths
 *     The width of each column's text, from `replySegments`.
 */
export function tableLines(rows: string[][], widths: number[]): TableLine[] {
	const border = (left: string, middle: string, right: string) =>
		left + widths.map(width => "─".repeat(width + 2)).join(middle) + right;
	const lines: TableLine[] = [{ kind: "border", text: border("╭", "┬", "╮") }];

	for (const [rowIndex, row] of rows.entries()) {
		const wrapped = row.map((cell, index) => wrap(inlineSpans(cell), widths[index]));
		const height = Math.max(...wrapped.map(cell => cell.length));

		for (let line = 0; line < height; line++) {
			lines.push({
				kind: "cells",
				cells: wrapped.map((cell, index) => {
					const spans = cell[line] ?? [];
					const padding = widths[index] - spans.reduce((length, span) => length + span.text.length, 0);

					return [...spans, { text: " ".repeat(padding), bold: false, code: false }];
				}),
				header: rowIndex === 0,
			});
		}

		if (rowIndex === 0 && rows.length > 1) {
			lines.push({ kind: "border", text: border("├", "┼", "┤") });
		}
	}

	lines.push({ kind: "border", text: border("╰", "┴", "╯") });

	return lines;
}

/**
 * Read one Markdown table row into its trimmed cells, or return null when the
 * line is not a table row. A table inside a quote is left for Claude Code to
 * draw as part of the quote.
 *
 * @param  {string}  line
 *     One line of the reply.
 */
function cells(line: string): string[] | null {
	if (!line.includes("|") || /^\s*>/.test(line)) {
		return null;
	}

	const trimmed = line.trim();
	const parts = trimmed.replace(/^\|/, "").replace(/\|$/, "").split(/(?<!\\)\|/);

	return parts.length > 1 || trimmed.startsWith("|")
		? parts.map(part => part.trim().replace(/\\\|/g, "|"))
		: null;
}

/**
 * Choose each column's text width so the boxed table fits the available width.
 * Columns start at their longest cell, and the widest one shrinks first, but
 * never below its longest word or 6 cells, whichever is shorter. Returns null
 * when the table cannot fit at those widths or holds wide characters.
 *
 * @param  {string[][]}  rows
 *     The table's cells, header row first.
 * @param  {number}  columns
 *     The width the reply is drawn into, in character cells.
 */
function tableWidths(rows: string[][], columns: number): number[] | null {
	if (rows.some(row => row.some(cell => WIDE_CHARACTER.test(cell)))) {
		return null;
	}

	const count = rows[0].length;
	const available = columns - (3 * count + 1);

	const widths = Array.from({ length: count }, (_, index) =>
		Math.max(1, ...rows.map(row => visibleText(inlineSpans(row[index])).length)));
	const floors = Array.from({ length: count }, (_, index) =>
		Math.min(6, Math.max(1, ...rows.flatMap(row => visibleText(inlineSpans(row[index])).split(/\s+/).map(word => word.length)))));

	while (widths.reduce((sum, width) => sum + width, 0) > available) {
		let widest = -1;

		for (let index = 0; index < widths.length; index++) {
			if (widths[index] > floors[index] && (widest === -1 || widths[index] > widths[widest])) {
				widest = index;
			}
		}

		if (widest === -1) {
			return null;
		}

		widths[widest]--;
	}

	return widths;
}

/**
 * Split a cell into plain, bold and code spans, removing the `**` and
 * backtick markers. Other inline Markdown is shown as written.
 *
 * @param  {string}  text
 *     The cell's Markdown.
 */
function inlineSpans(text: string): CellSpan[] {
	const spans: CellSpan[] = [];
	const pattern = /(\*\*([^*]+)\*\*|`([^`]+)`)/g;
	let start = 0;

	for (const match of text.matchAll(pattern)) {
		if (match.index > start) {
			spans.push({ text: text.slice(start, match.index), bold: false, code: false });
		}

		spans.push({ text: match[2] ?? match[3], bold: match[2] !== undefined, code: match[3] !== undefined });
		start = match.index + match[0].length;
	}

	if (start < text.length) {
		spans.push({ text: text.slice(start), bold: false, code: false });
	}

	return spans;
}

/**
 * Join a cell's spans into the text that appears on screen, for measuring.
 *
 * @param  {CellSpan[]}  spans
 *     The cell's spans.
 */
function visibleText(spans: CellSpan[]): string {
	return spans.map(span => span.text).join("");
}

/**
 * Wrap a cell onto lines no wider than its column, breaking at spaces where it
 * can and keeping each span's style. An empty cell gives one empty line.
 *
 * @param  {CellSpan[]}  spans
 *     The cell's spans.
 * @param  {number}  width
 *     The column's text width.
 */
function wrap(spans: CellSpan[], width: number): CellSpan[][] {
	const text = visibleText(spans);
	const lines: CellSpan[][] = [];
	let start = 0;

	while (start < text.length) {
		let end = Math.min(start + width, text.length);

		if (end < text.length && !/\s/.test(text[end]) && !/\s/.test(text[end - 1])) {
			const breakAt = text.lastIndexOf(" ", end - 1);

			if (breakAt > start) {
				end = breakAt;
			}
		}

		const parts: CellSpan[] = [];
		let offset = 0;

		for (const span of spans) {
			const from = Math.max(start - offset, 0);
			const to = Math.min(end - offset, span.text.length);

			if (to > from) {
				parts.push({ ...span, text: span.text.slice(from, to) });
			}

			offset += span.text.length;
		}

		lines.push(parts);
		start = end;

		while (text[start] === " ") {
			start++;
		}
	}

	return lines.length > 0 ? lines : [[]];
}
