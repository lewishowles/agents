import type { On, RenderElement } from "claude-code";
import { expect, test } from "claude-code/testing";

import { paletteFor, palettes } from "../hooks/palette";
import { replySegments } from "../hooks/reply";

/** A stand-in for Claude Code's own drawing, which a hook gets when it calls `next`. */
const stock: RenderElement = { type: "Text", props: {}, children: ["stock row"] };

/**
 * Answer the theme and environment lookups the skin makes, and draw the stand-in row for anything it passes on.
 *
 * @param  {On}  on
 *     The test's hook registration.
 * @param  {string}  theme
 *     The Claude Code theme setting to report.
 */
function host(on: On, theme = "dark") {
	on("session.start", () => ({ cwd: "/work" }));
	on("turn.start", ($, event) => ({ turnId: event.turnId }));
	on("turn.complete", () => ({ text: "" }));
	on("tool.call", () => ({ result: { stdout: "", stderr: "" } }));
	on("config.list", () => ({ value: [{ key: "theme", label: "Theme", kind: "enum", value: theme, provider: { kind: "engine" }, isLocked: false }] as never }));
	on("env.get", () => ({ value: undefined }));
	on("ui.render", () => stock);
}

/**
 * Build a request to draw one transcript component.
 *
 * @param  {string}  component
 *     The component to draw, such as `ToolUse`.
 * @param  {object}  props
 *     The component's props.
 * @param  {"terminal"|"desktop"}  surface
 *     Where the transcript is drawn.
 */
function site(component: string, props: object, surface: "terminal" | "desktop" = "terminal") {
	return { plugin: "skin", component, props, requestId: "row-1", surface, viewport: { columns: 100, rows: 30 } } as const;
}

test("tool headers show a summary and state colour on both surfaces", async ($, on) => {
	host(on);

	for (const surface of ["terminal", "desktop"] as const) {
		const base = { tool_use_id: "tool-1", tool: "Bash", input: { command: "bun test" }, isInterrupted: false, output: { stdout: "ok" } };
		const done = await $.ui.mount(site("ToolUse", { ...base, isRunning: false, isErrored: false }, surface));
		const heading = await done.find({ type: "Text", text: /Bash/ });

		expect(await done.find({ type: "Text", text: /bun test/ })).toBeDefined();
		expect(JSON.stringify(heading)).toContain(palettes.mocha.accent);
		expect(JSON.stringify(await done.find({ type: "Text", text: /●─/ }))).toContain(palettes.mocha.done);
		expect((await done.find({ type: "Box" }))?.props.marginTop).toBe(1);

		await done.unmount();

		const failed = await $.ui.mount(site("ToolUse", { ...base, isRunning: false, isErrored: true }, surface));

		expect(JSON.stringify(await failed.find({ type: "Text", text: /●─/ }))).toContain(palettes.mocha.failed);

		await failed.unmount();

		const running = await $.ui.mount(site("ToolUse", { ...base, isRunning: true, isErrored: false, output: undefined }, surface));

		expect(JSON.stringify(await running.find({ type: "Text", text: /●─/ }))).toContain(palettes.mocha.running);

		await running.unmount();

		const interrupted = await $.ui.mount(site("ToolUse", { ...base, isRunning: false, isErrored: false, isInterrupted: true }, surface));

		expect(JSON.stringify(await interrupted.find({ type: "Text", text: /●─/ }))).toContain(palettes.mocha.muted);
		expect(await interrupted.find({ type: "Text", text: /interrupted/ })).toBeDefined();

		await interrupted.unmount();
	}
});

test("a finished tool row with output still shows the skin header", async ($, on) => {
	host(on);

	const finished = await $.ui.mount(site("ToolUse", {
		tool_use_id: "tool-1", tool: "Read", input: { file_path: "/work/a.ts" },
		isRunning: false, isErrored: false, isInterrupted: false, output: "file contents",
	}));

	expect(await finished.find({ type: "Text", text: /●─/ })).toBeDefined();
	expect(await finished.find({ type: "Text", text: /\/work\/a\.ts/ })).toBeDefined();
	expect(await finished.find({ type: "Text", text: "stock row" })).toBeUndefined();
});

test("Bash result keeps Claude's output inside a round card", async ($, on) => {
	host(on, "light");

	const result = await $.ui.mount(site("ToolResult", { tool_use_id: "tool-1", tool: "Bash", output: { stdout: "ok" }, isErrored: false }));
	const card = await result.find({ type: "Box" });

	expect(card?.props.borderStyle).toBe("round");
	expect(card?.props.borderColor).toBe(palettes.latte.border);
	expect(await result.find({ type: "Text", text: "stock row" })).toBeDefined();
});

test("footer shows duration, zero tools, and a blank line", async ($, on) => {
	host(on);

	const footer = await $.ui.mount(site("TurnDuration", { word: "Baked", durationMs: 64_000 }));

	expect(await footer.find({ type: "Text", text: /Done in 1m 4s · 0 tools/ })).toBeDefined();
	expect((await footer.find({ type: "Box" }))?.props.marginTop).toBe(1);
});

test("a finished footer keeps its main-turn count after a new turn starts", async ($, on) => {
	host(on);

	await $.turn.start({ text: "first", turnId: "turn-1" });
	await $.tool.call({ tool: "Bash", command: "pwd" });
	await $.tool.call({ tool: "Bash", command: "ls" });
	await $.tool.call({ tool: "Bash", command: "ls", agentId: "subagent-1" } as never);
	await $.turn.complete({ answer: "", durationMs: 2000, isAborted: false, turnId: "turn-1", reason: "answer" });

	const oldFooter = await $.ui.mount(site("TurnDuration", { word: "Baked", durationMs: 2000 }));
	expect(await oldFooter.find({ type: "Text", text: /Done in 2s · 2 tools/ })).toBeDefined();

	await $.turn.start({ text: "second", turnId: "turn-2" });
	expect(await oldFooter.find({ type: "Text", text: /Done in 2s · 2 tools/ })).toBeDefined();

	await $.tool.call({ tool: "Bash", command: "date" });
	await $.turn.complete({ answer: "", durationMs: 3000, isAborted: false, turnId: "turn-2", reason: "answer" });

	const newFooter = await $.ui.mount({ ...site("TurnDuration", { word: "Baked", durationMs: 3000 }), requestId: "row-2" });
	expect(await newFooter.find({ type: "Text", text: /Done in 3s · 1 tool/ })).toBeDefined();
	expect(await oldFooter.find({ type: "Text", text: /Done in 2s · 2 tools/ })).toBeDefined();
});

test("palette follows a light terminal background when theme is automatic", () => {
	expect(paletteFor("auto", "0;7")).toBe(palettes.latte);
	expect(paletteFor("auto", "0;15")).toBe(palettes.latte);
	expect(paletteFor("auto", "7;0")).toBe(palettes.mocha);
});

test("reply tables have a boxed grid and wrap at narrow widths", async ($, on) => {
	host(on, "light");

	const reply = await $.ui.mount({
		...site("AssistantMessage", {
			text: "Before\n\n| Name | Detail |\n| --- | --- |\n| First | A longer description |\n\nAfter",
			isFirstOfReply: true,
		}),
		viewport: { columns: 28, rows: 30 },
	});

	expect(await reply.find({ type: "Markdown", text: /Before/ })).toBeDefined();
	expect(await reply.find({ type: "Markdown", text: /After/ })).toBeDefined();
	expect(JSON.stringify(await reply.find({ type: "Text", text: /╭.*┬.*╮/ }))).toContain(palettes.latte.border);
	expect(JSON.stringify(await reply.find({ type: "Text", text: /Name/ }))).toContain(palettes.latte.accent);

	const description = await reply.findAll({ type: "Text", text: /description/ });

	expect(description.some(node => node.text === "description")).toBe(true);
	expect(description.some(node => node.text.includes("longer description"))).toBe(false);
	expect(await reply.find({ type: "Text", text: /╰.*┴.*╯/ })).toBeDefined();
	expect((await reply.find({ key: "segment-1" }))?.props.marginTop).toBe(1);
	expect((await reply.find({ key: "segment-2" }))?.props.marginTop).toBe(1);
	expect((await reply.find({ type: "Markdown", text: "Before" }))?.text).toBe("Before");
	expect((await reply.find({ type: "Markdown", text: "After" }))?.text).toBe("After");
});

test("roomy tables keep whole cells and draw inline bold and code", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "| Name | Detail |\n| --- | --- |\n| **Strong** | A long detail with `code` and │ a divider |",
		isFirstOfReply: true,
	}));
	const bold = await reply.findAll({ type: "Text", text: "Strong" });
	const code = await reply.findAll({ type: "Text", text: "code" });

	expect(bold.some(node => node.props.bold === true)).toBe(true);
	expect(code.some(node => node.props.color === palettes.mocha.accent)).toBe(true);
	expect(await reply.find({ type: "Text", text: "A long detail with " })).toBeDefined();
	expect(await reply.find({ type: "Text", text: " and │ a divider" })).toBeDefined();
	expect(await reply.find({ type: "Text", text: "**Strong**" })).toBeUndefined();
	expect(await reply.find({ type: "Text", text: "`code`" })).toBeUndefined();
});

test("a final Over to you quote appears in an accent card", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "Explanation.\n\n> **Over to you**\n> **1.** Pick a colour.\n> → **Purple.** It matches the theme.",
		isFirstOfReply: true,
	}));
	const card = await reply.find({ key: "card-1" });

	expect(card?.props.borderColor).toBe(palettes.mocha.accent);
	expect((await reply.find({ key: "card-title-1" }))?.props.top).toBe(-1);
	expect(await reply.find({ type: "Text", text: /Over to you/ })).toBeDefined();
	expect(await reply.find({ type: "Markdown", text: /\*\*1\.\*\* Pick a colour/ })).toBeDefined();
	expect(await reply.find({ type: "Markdown", text: /→ \*\*Purple\.\*\*/ })).toBeDefined();
});

test("a single Over to you request keeps the text after its label", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "Please review.\n\n> **Over to you:** Reset the Implementer?",
		isFirstOfReply: true,
	}));

	expect(await reply.find({ key: "card-1" })).toBeDefined();
	expect(await reply.find({ type: "Markdown", text: "Reset the Implementer?" })).toBeDefined();
});

test("plain replies keep the engine drawing", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "An ordinary answer.", isFirstOfReply: true,
	}));

	expect(await reply.find({ type: "Text", text: "stock row" })).toBeDefined();
});

test("the opening reply has a bullet and later blocks keep its two-cell gutter", async ($, on) => {
	host(on);

	const text = "| A | B |\n| --- | --- |\n| 1 | 2 |";
	const first = await $.ui.mount(site("AssistantMessage", { text, isFirstOfReply: true }));
	const later = await $.ui.mount({ ...site("AssistantMessage", { text, isFirstOfReply: false }), requestId: "row-2" });

	expect((await first.findAll({ type: "Text", text: "⏺ " })).some(node => node.text === "⏺ ")).toBe(true);
	expect((await first.findAll({ type: "Box" })).some(node => node.props.width === 2)).toBe(true);
	expect(await later.find({ type: "Text", text: "⏺" })).toBeUndefined();
	expect((await later.findAll({ type: "Box" })).some(node => node.props.width === 2)).toBe(true);
});

test("short table rows are padded and extra cells are dropped", () => {
	const segments = replySegments("| A | B |\n| --- | --- |\n| one |\n| two | three | extra |", 80);
	const table = segments?.find(segment => segment.kind === "table");

	expect(table?.kind).toBe("table");

	if (table?.kind === "table") {
		expect(table.rows[1]).toEqual(["one", ""]);
		expect(table.rows[2]).toEqual(["two", "three"]);
	}
});

test("tables below their minimum column widths keep stock drawing", async ($, on) => {
	host(on);

	const reply = await $.ui.mount({
		...site("AssistantMessage", { text: "| Header | Detail |\n| --- | --- |\n| value | another value |", isFirstOfReply: true }),
		viewport: { columns: 18, rows: 30 },
	});

	expect(await reply.find({ type: "Text", text: "stock row" })).toBeDefined();
});

test("wide characters leave a table to stock drawing", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "| Name | Value |\n| --- | --- |\n| 東京 | 😀 |", isFirstOfReply: true,
	}));

	expect(await reply.find({ type: "Text", text: "stock row" })).toBeDefined();
});

test("a table inside a code fence keeps stock drawing", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "```md\n| A | B |\n| --- | --- |\n| one | two |\n```", isFirstOfReply: true,
	}));

	expect(await reply.find({ type: "Text", text: "stock row" })).toBeDefined();
});

test("a short or different closing fence leaves its table as code", () => {
	expect(replySegments("````md\n```\n| A | B |\n| --- | --- |\n| one | two |", 80)).toBeNull();
	expect(replySegments("~~~md\n```\n| A | B |\n| --- | --- |\n| one | two |", 80)).toBeNull();
	expect(replySegments("    ```md\n| A | B |\n| --- | --- |\n| one | two |", 80)).not.toBeNull();
});

test("prose after an Over to you quote leaves it to stock drawing", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "> **Over to you:** Reset?\n\nMore prose.", isFirstOfReply: true,
	}));

	expect(await reply.find({ type: "Text", text: "stock row" })).toBeDefined();
});

test("a separate earlier quote does not hide the final Over to you card", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "> Earlier note.\n\n> **Over to you:** Reset?", isFirstOfReply: true,
	}));

	expect(await reply.find({ key: "card-1" })).toBeDefined();
	expect(await reply.find({ type: "Markdown", text: "Reset?" })).toBeDefined();
});

test("summary replies keep the engine drawing even when they contain a table", async ($, on) => {
	host(on);

	const reply = await $.ui.mount(site("AssistantMessage", {
		text: "| A | B |\n| --- | --- |\n| 1 | 2 |",
		isFirstOfReply: true, isSummary: true, onScreen: null,
	}));

	expect(await reply.find({ type: "Text", text: "stock row" })).toBeDefined();
});
