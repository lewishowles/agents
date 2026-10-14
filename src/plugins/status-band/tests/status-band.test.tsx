import type { On, RenderElement } from "claude-code";
import { expect, test } from "claude-code/testing";

import { checkpointLimit, formatMeter, formatTaskLine, truncateLine } from "../hooks/format";

/** A stand-in for the band content that `next` returns from another plugin. */
const stock: RenderElement = { type: "Text", props: {}, children: ["existing band"] };

/** The host values that vary between band scenarios. */
type HostValues = {
	/** Tasks returned by `progress task list`. */
	tasks?: object[];
	/** Chunks returned by `progress chunk list`. */
	chunks?: object[];
	/** Whether the progress commands report an error. */
	progressFails?: boolean;
	/** Context window fill supplied by the host. */
	percent?: number;
	/** Context tokens supplied when fill is unavailable. */
	tokens?: number;
	/** The counter file's contents, or null when the file is missing. */
	calls?: string | null;
	/** The HCOM_TAG value used to select a role limit. */
	tag?: string;
	/** The AGENT_TOOL_CALL_LIMIT value that overrides the role limit. */
	override?: string;
};

/**
 * Answer the host calls made while the band draws, without running progress or reading a real counter.
 *
 * @param  {On}  on
 *     The test's hook registration.
 * @param  {HostValues}  values
 *     The progress, usage, and checkpoint figures to report.
 */
function host(on: On, values: HostValues = {}) {
	on("session.id", () => ({ value: "session-1" }));
	on("session.usage", () => ({ value: { startedAt: 0, context: { window: 200_000, percent: values.percent, tokens: values.tokens }, rateLimits: [] } }));
	on("env.get", ($, event) => ({ value: event.name === "TMPDIR" ? "/tmp/" : event.name === "HCOM_TAG" ? values.tag : values.override }));
	on("fs.read", () => {
		if (values.calls === null) {
			throw new Error("ENOENT");
		}

		return { value: values.calls ?? "0\n" };
	});
	on("process.run", ($, event) => ({
		value: {
			exitCode: values.progressFails ? 1 : 0,
			stdout: JSON.stringify({ data: { items: event.argv[1] === "task" ? values.tasks ?? [] : values.chunks ?? [] } }),
			stderr: "",
		} as never,
	}));
	on("ui.render", () => stock);
}

/**
 * Build a request to draw the band at the given width.
 *
 * @param  {number}  columns
 *     The number of columns the band may use.
 * @param  {boolean}  hasSurvey
 *     Whether Claude Code's survey owns the band.
 */
function bandRequest(columns = 89, hasSurvey = false) {
	return {
		plugin: "status-band", component: "AbovePrompt", requestId: "band-1", surface: "terminal",
		viewport: { columns: columns + 5, rows: 30 },
		props: { hasSurvey, isWorking: false, maxRows: 4, bodyColumns: columns, scroll: { offset: 0, bodyRows: 4 }, view: {} },
	} as const;
}

test("The task row shows the newest task and its active chunk", async ($, on) => {
	host(on, {
		tasks: [
			{ id: "older", title: "Earlier task", started_at: "2026-10-10T10:00:00+00:00" },
			{ id: "newer", title: "Current task", started_at: "2026-10-11T10:00:00+00:00" },
		],
		chunks: [
			{ title: "First part", position: 1, status: "completed" },
			{ title: "Draw the band", position: 2, status: "active" },
			{ title: "Later part", position: 3, status: "pending" },
		],
		percent: 42,
		calls: "17\n",
		tag: "team-implementer",
	});

	const band = await $.ui.mount(bandRequest());

	expect(await band.find({ type: "Text", text: /Current task \+1 more · chunk 2\/3: Draw the band/ })).toBeDefined();
	expect(await band.find({ type: "Text", text: /Context 42%.*tools 17\/40/ })).toBeDefined();
	expect(await band.find({ type: "Text", text: "existing band" })).toBeDefined();
});

test("The band keeps the earlier band content in a Box with no width", async ($, on) => {
	host(on);

	const band = await $.ui.mount(bandRequest());
	const drawing = await band.drawn();

	expect(await band.find({ type: "Text", text: "existing band" })).toBeDefined();
	expect(drawing.type).toBe("Box");

	if (drawing.type === "Box") {
		expect(drawing.props?.width).toBeUndefined();
	}
});

test("The task row leaves out the chunk when none is active", async ($, on) => {
	host(on, {
		tasks: [{ id: "task", title: "Current task", started_at: "2026-10-11T10:00:00+00:00" }],
		chunks: [{ title: "Next chunk", position: 1, status: "pending" }],
	});

	const band = await $.ui.mount(bandRequest());
	const task = await band.find({ type: "Text", text: /Task: Current task/ });

	expect(task).toBeDefined();
	expect(task?.text).not.toContain("chunk");
});

test("The task row stays hidden without a task", async ($, on) => {
	host(on, { percent: 20 });

	const band = await $.ui.mount(bandRequest());

	expect(await band.find({ type: "Text", text: /Task:/ })).toBeUndefined();
	expect(await band.find({ type: "Text", text: /tools 0\/20/ })).toBeDefined();
});

test("The task row stays hidden when progress fails", async ($, on) => {
	host(on, {
		progressFails: true,
		tasks: [{ id: "task", title: "A task", started_at: "2026-10-11T10:00:00+00:00" }],
	});

	const failed = await $.ui.mount(bandRequest());

	expect(await failed.find({ type: "Text", text: /Task:/ })).toBeUndefined();
	expect(await failed.find({ type: "Text", text: /tools 0\/20/ })).toBeDefined();
});

test("The meter hides tool figures when the counter cannot be read", async ($, on) => {
	host(on, { calls: null, percent: 20 });

	const band = await $.ui.mount(bandRequest());
	const meter = await band.find({ type: "Text", text: /Context 20%/ });

	expect(meter).toBeDefined();
	expect(meter?.props.color).toBe("subtle");
	expect(await band.find({ type: "Text", text: /tools|checkpoint soon/ })).toBeUndefined();
});

test("The band steps aside while a survey is open", async ($, on) => {
	host(on, { tasks: [{ id: "task", title: "A task", started_at: "2026-10-11T10:00:00+00:00" }] });

	const band = await $.ui.mount(bandRequest(89, true));

	expect(await band.find({ type: "Text", text: /Task:|Context/ })).toBeUndefined();
	expect(await band.find({ type: "Text", text: "existing band" })).toBeDefined();
});

test("Long task and meter rows fit the available columns", () => {
	const row = formatTaskLine({
		title: "A very long task title that could take the entire row by itself",
		more: 2,
		chunk: { title: "A similarly long active chunk title that could also wrap", position: 2, total: 4 },
	}, 50);

	expect(Array.from(row).length).toBeLessThanOrEqual(50);
	expect(row).toContain("+2 more");
	expect(row).toContain("chunk 2/4");
	expect(row).toContain("…");
	expect(truncateLine("hello world", 6)).toBe("hello…");
	expect(Array.from(formatMeter({ percent: 99 }, 19, 20, 40)).length).toBeLessThanOrEqual(40);
});

test("A short chunk title leaves room for the full task title", () => {
	const title = "T".repeat(60);
	const row = formatTaskLine({ title, more: 0, chunk: { title: "Fix", position: 1, total: 1 } }, 89);

	expect(row).toContain(title);
	expect(row).toContain("chunk 1/1: Fix");
	expect(row).not.toContain("…");
});

test("Both rendered rows stay under 90 columns in a wide terminal", async ($, on) => {
	host(on, {
		tasks: [{ id: "task", title: "T".repeat(150), started_at: "2026-10-11T10:00:00+00:00" }],
		chunks: [{ title: "C".repeat(150), position: 1, status: "active" }],
		percent: 85,
		calls: "20\n",
	});

	const band = await $.ui.mount(bandRequest(120));
	const task = await band.find({ type: "Text", text: /Task:/ });
	const meter = await band.find({ type: "Text", text: /Context 85%/ });

	expect(task).toBeDefined();
	expect(meter).toBeDefined();
	expect(Array.from(task?.text ?? "").length).toBeLessThanOrEqual(89);
	expect(Array.from(meter?.text ?? "").length).toBeLessThanOrEqual(89);
	expect(meter?.text).toContain("checkpoint reached");
	expect(meter?.props.color).toBe("warning");
});

test("The meter uses tokens without fill and warns near the checkpoint", () => {
	expect(formatMeter({ tokens: 12_345 }, 18, 20, 89)).toContain("Context 12,345 tokens");
	expect(formatMeter({ tokens: 12_345 }, 18, 20, 89)).toContain("checkpoint soon");
	expect(formatMeter({ tokens: 12_345 }, null, 20, 89)).toBe("Context 12,345 tokens");
	expect(formatMeter({}, 0, 20, 89)).toContain("Context pending");
	expect(formatMeter({ percent: 50 }, 16, 20, 89)).not.toContain("checkpoint soon");
	expect(formatMeter({ percent: 50 }, 19, 20, 89)).toContain("checkpoint soon");
	expect(formatMeter({ percent: 50 }, 20, 20, 89)).toContain("checkpoint reached");
	expect(formatMeter({ percent: 50 }, 20, 20, 89)).not.toContain("checkpoint soon");
});

test("The checkpoint limit follows the tag and a valid override", () => {
	expect(checkpointLimit(undefined, undefined)).toBe(20);
	expect(checkpointLimit("team-scout", undefined)).toBe(40);
	expect(checkpointLimit("scout", undefined)).toBe(40);
	expect(checkpointLimit("team-implementer", undefined)).toBe(40);
	expect(checkpointLimit("team-orchestrator", undefined)).toBe(20);
	expect(checkpointLimit("team-scout", "12")).toBe(12);
	expect(checkpointLimit("team-scout", "0")).toBe(40);
});
