import type { On, RenderElement } from "claude-code";
import { expect, test } from "claude-code/testing";

import { checkpointLimit, deriveTeam, formatCheckpoint, formatMeter, formatPeers, formatTaskLine, hcomWaitArgv, keepSessionMessages, truncateLine } from "../hooks/format";
import type { HcomMessage, HcomPeer } from "../hooks/format";

// A stand-in for the band content that `next` returns from another plugin.
const stock: RenderElement = { type: "Text", props: {}, children: ["existing band"] };

// The host values that vary between band scenarios.
type HostValues = {
	// Tasks returned by `progress task list`.
	tasks?: object[];
	// Chunks returned by `progress chunk list`.
	chunks?: object[];
	// Whether the progress commands report an error.
	progressFails?: boolean;
	// Context window fill supplied by the host.
	percent?: number;
	// Context tokens supplied when fill is unavailable.
	tokens?: number;
	// The counter file's contents, or null when the file is missing.
	calls?: string | null;
	// The HCOM_TAG value used to select a role limit.
	tag?: string;
	// The AGENT_TOOL_CALL_LIMIT value that overrides the role limit.
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

test("The peer row shows only this team's roles, statuses, and outstanding wait ages", () => {
	const agents: HcomPeer[] = [
		{ name: "team-orchestrator-hepu", tag: "team-orchestrator", status: "active", status_age_seconds: 9 },
		{ name: "team-scout-heti", tag: "team-scout", status: "listening", status_age_seconds: 80 },
		{ name: "team-extra-scout-hata", tag: "team-extra-scout", status: "active", status_age_seconds: 2 },
		{ name: "other-scout-kohi", tag: "other-scout", status: "active", status_age_seconds: 2 },
	];
	const messages: HcomMessage[] = [{
		id: "10", ts: "2026-10-16T12:00:00Z", from: "team-orchestrator-hepu", delivered_to: ["heti"],
		intent: "request", text: "Please check this",
	}];
	const team = deriveTeam(agents, messages, "hepu", "team-orchestrator", Date.parse("2026-10-16T12:02:00Z"), 10);

	expect(team?.peers).toEqual([{ role: "scout", status: "listening", ageSeconds: 90, waitSeconds: 120 }]);
	expect(formatPeers(team?.peers ?? [], 89)).toBe("Peers: scout listening 1m (waiting 2m)");
	expect(Array.from(formatPeers(team?.peers ?? [], 24)).length).toBeLessThanOrEqual(24);
});

test("A reply clears the wait mark and a later request restores it", () => {
	const agents: HcomPeer[] = [
		{ name: "team-orchestrator-hepu", tag: "team-orchestrator", status: "active", status_age_seconds: 0 },
		{ name: "team-scout-heti", tag: "team-scout", status: "active", status_age_seconds: 0 },
	];
	const messages: HcomMessage[] = [
		{ id: "1", ts: "2026-10-16T12:00:00Z", from: "hepu", delivered_to: ["team-scout-heti"], intent: "request", text: "First" },
		{ id: "2", ts: "2026-10-16T12:01:00Z", from: "heti", delivered_to: ["hepu"], intent: "inform", reply_to: "1", text: "Done" },
		{ id: "3", ts: "2026-10-16T12:02:00Z", from: "hepu", delivered_to: ["heti"], intent: "request", text: "Second" },
	];

	expect(deriveTeam(agents, messages.slice(0, 2), "hepu", "team-orchestrator", Date.parse("2026-10-16T12:03:00Z"))?.peers[0]?.waitSeconds).toBeUndefined();
	expect(deriveTeam(agents, messages, "hepu", "team-orchestrator", Date.parse("2026-10-16T12:03:00Z"))?.peers[0]?.waitSeconds).toBe(60);
});

test("Only this session's messages count towards the retained message limit", () => {
	const agents: HcomPeer[] = [
		{ name: "team-orchestrator-hepu", tag: "team-orchestrator", status: "active", status_age_seconds: 0 },
		{ name: "team-scout-heti", tag: "team-scout", status: "active", status_age_seconds: 0 },
	];
	const request: HcomMessage = {
		id: "1", ts: "2026-10-16T12:00:00Z", from: "team-orchestrator-hepu", delivered_to: ["heti"],
		intent: "request", text: "Please check this",
	};
	const otherMessages: HcomMessage[] = Array.from({ length: 1000 }, (_, index) => ({
		id: String(index + 2), ts: "2026-10-16T12:01:00Z", from: "other-scout-kohi", delivered_to: ["other-orchestrator-hoku"],
		intent: "inform", text: "Unrelated update",
	}));
	const reply: HcomMessage = {
		id: "1002", ts: "2026-10-16T12:02:00Z", from: "heti", delivered_to: ["team-orchestrator-hepu"],
		intent: "inform", reply_to: "1", text: "Done",
	};
	const messages = keepSessionMessages([request, ...otherMessages, request], "hepu", 1000);
	const team = deriveTeam(agents, messages, "hepu", "team-orchestrator", Date.parse("2026-10-16T12:02:00Z"));

	expect(messages).toEqual([request]);
	expect(team?.peers[0]?.waitSeconds).toBe(120);
	expect(keepSessionMessages([...messages, reply], "hepu", 1000)).toEqual([request, reply]);
	expect(keepSessionMessages([request, reply], "hepu", 1)).toEqual([reply]);
});

test("A peer's onward request leaves the wait mark in place", () => {
	const agents: HcomPeer[] = [
		{ name: "team-orchestrator-hepu", tag: "team-orchestrator", status: "active", status_age_seconds: 0 },
		{ name: "team-scout-heti", tag: "team-scout", status: "active", status_age_seconds: 0 },
	];
	const messages: HcomMessage[] = [
		{ id: "1", ts: "2026-10-16T12:00:00Z", from: "hepu", delivered_to: ["heti"], intent: "request", text: "Please investigate" },
		{ id: "2", ts: "2026-10-16T12:01:00Z", from: "heti", delivered_to: ["third-agent"], intent: "request", reply_to: "1", text: "Please check this part" },
	];

	expect(deriveTeam(agents, messages, "hepu", "team-orchestrator", Date.parse("2026-10-16T12:02:00Z"))?.peers[0]?.waitSeconds).toBe(120);
});

test("A stopped peer needs a decision until this session sends another message", () => {
	const agents: HcomPeer[] = [
		{ name: "team-orchestrator-hepu", tag: "team-orchestrator", status: "active", status_age_seconds: 0 },
		{ name: "team-implementer-hesu", tag: "team-implementer", status: "listening", status_age_seconds: 0 },
	];
	const stoppedMessage: HcomMessage = {
		id: "2", ts: "2026-10-16T12:01:00Z", from: "team-implementer-hesu", delivered_to: ["team-orchestrator-hepu"],
		intent: "inform", text: "State: stopped; human decision required. Safe to reset: no",
	};
	const laterReport: HcomMessage = {
		id: "4", ts: "2026-10-16T12:03:00Z", from: "hesu", delivered_to: ["hepu"],
		intent: "inform", text: "Safe to reset: yes",
	};
	const messages: HcomMessage[] = [
		{ id: "1", ts: "2026-10-16T12:00:00Z", from: "hesu", delivered_to: ["hepu"], intent: "inform", text: "Safe to reset: yes" },
		stoppedMessage,
		{ id: "3", ts: "2026-10-16T12:02:00Z", from: "hepu", delivered_to: ["hesu"], intent: "request", text: "Continue" },
		laterReport,
	];

	expect(deriveTeam(agents, messages.slice(0, 1), "hepu", "team-orchestrator", Date.parse("2026-10-16T12:03:00Z"))?.checkpoints).toEqual([]);
	expect(deriveTeam(agents, messages.slice(0, 2), "hepu", "team-orchestrator", Date.parse("2026-10-16T12:03:00Z"))?.checkpoints).toEqual(["implementer"]);
	expect(deriveTeam(agents, messages.slice(0, 3), "hepu", "team-orchestrator", Date.parse("2026-10-16T12:03:00Z"))?.checkpoints).toEqual([]);
	expect(deriveTeam(agents, [stoppedMessage, laterReport], "hepu", "team-orchestrator", Date.parse("2026-10-16T12:04:00Z"))?.checkpoints).toEqual([]);
	expect(formatCheckpoint(["implementer"], 89)).toBe("Implementer stopped: continue or reset?");
	expect(formatCheckpoint(["implementer", "scout"], 89)).toBe("Implementer and Scout stopped: continue or reset?");
	expect(formatCheckpoint(["implementer", "scout", "reviewer"], 89)).toBe("Implementer, Scout and Reviewer stopped: continue or reset?");
	expect(Array.from(formatCheckpoint(["implementer", "scout", "reviewer"], 24)).length).toBeLessThanOrEqual(24);
});

test("HCOM rows stay hidden when the session identity does not resolve", () => {
	const agents: HcomPeer[] = [{ name: "team-scout-heti", tag: "team-scout", status: "active", status_age_seconds: 2 }];

	expect(deriveTeam(agents, [], "unknown", "team-orchestrator", Date.now())).toBeNull();
	expect(deriveTeam(agents, [], "heti", "other-scout", Date.now())).toBeNull();
	expect(deriveTeam(agents, [], "heti", "scout", Date.now())).toBeNull();
});

test("The HCOM wait uses an event ID strictly after the last event read", () => {
	const argv = hcomWaitArgv(164796, "hepu", 1000);

	expect(argv).toEqual(["hcom", "events", "--full", "--sql", "id > 164796", "--wait", "30", "--last", "1000", "--name", "hepu"]);
	expect(argv).not.toContain("--after");
});
