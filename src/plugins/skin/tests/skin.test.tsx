import type { On, RenderElement } from "claude-code";
import { expect, test } from "claude-code/testing";

import { paletteFor, palettes } from "../hooks/palette";

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
