import type { EngineInterface, Register } from "claude-code";

import { CHECKPOINT_WARNING_REMAINING, checkpointLimit, deriveTeam, formatCheckpoint, formatMeter, formatPeers, formatTaskLine, hcomWaitArgv, keepSessionMessages } from "./format";
import type { HcomMessage, HcomPeer, TaskLine } from "./format";

// The widest a band row may be, so that it stays under 90 columns in narrow terminal panes.
const MAX_COLUMNS = 89;

// The most HCOM messages kept in memory, and the most events one wait returns.
const MAX_HCOM_EVENTS = 1000;

// This session's HCOM team members, recent messages, and the last event read.
type HcomState = {
	// The team's latest agents and their status ages.
	agents: HcomPeer[];
	// Recent messages to and from this session, used to find replies and stopped teammates.
	messages: HcomMessage[];
	// This session's short or full HCOM name.
	name: string;
	// This session's full team and role tag.
	tag: string;
	// When the agent statuses were last fetched, in milliseconds.
	statusFetchedAt: number;
	// The highest HCOM event ID already read.
	lastId: number;
};

// The latest HCOM team snapshot, or null outside a team or when the first HCOM read fails.
let hcomState: HcomState | null = null;

// Whether HCOM reading has begun, so a repeated session start does not begin a second reader.
let hcomStarted = false;

// Draw the task, meter, and HCOM team rows above the prompt, and redraw them after each tool call, turn, and HCOM event.
export const register: Register = on => {
	on("session.start", async ($, event, next) => {
		const result = await next(event);

		if (!hcomStarted) {
			hcomStarted = true;
			void startHcom($);
		}

		return result;
	});

	on("tool.call", async ($, event, next) => {
		const result = await next(event);

		$.ui.invalidate("ui.render");

		return result;
	});

	on("turn.complete", async ($, event, next) => {
		const result = await next(event);

		$.ui.invalidate("ui.render");

		return result;
	});

	on("ui.render", { component: "AbovePrompt" }, async ($, event, next) => {
		// A survey takes the space above the prompt while it is open, so the band steps aside.
		if (event.props.hasSurvey) {
			return next(event);
		}

		const { Box, Text } = $.ui.resolve(event);
		const columns = Math.min(MAX_COLUMNS, event.props.bodyColumns);
		const [task, context, calls, limit] = await Promise.all([
			loadTask($),
			$.session.usage().then(usage => usage.context).catch(() => ({})),
			readCalls($),
			loadLimit($),
		]);
		const meter = formatMeter(context, calls, limit, columns);
		const now = Date.now();
		const team = hcomState && deriveTeam(
			hcomState.agents,
			hcomState.messages,
			hcomState.name,
			hcomState.tag,
			now,
			Math.floor((now - hcomState.statusFetchedAt) / 1000),
		);
		const earlierBand = await next(event);

		// Claude Code refuses to draw its own band content inside a Box that sets a width, so the formatters keep
		// each row within the width instead.
		return (
			<Box flexDirection="column">
				{task && <Text wrap="truncate-end" color="subtle">{formatTaskLine(task, columns)}</Text>}
				<Text wrap="truncate-end" color={calls !== null && calls >= limit - CHECKPOINT_WARNING_REMAINING ? "warning" : "subtle"}>{meter}</Text>
				{team && team.peers.length > 0 && <Text wrap="truncate-end" color="subtle">{formatPeers(team.peers, columns)}</Text>}
				{team && team.checkpoints.length > 0 && <Text wrap="truncate-end" color="warning">{formatCheckpoint(team.checkpoints, columns)}</Text>}
				{earlierBand}
			</Box>
		);
	});
};

/**
 * Read this session's HCOM team members and recent messages, then keep watching for new events.
 *
 * The team rows stay hidden when the session is not in an HCOM team or the first HCOM read fails.
 *
 * @param  {EngineInterface}  $
 *     The host services for this session.
 */
async function startHcom($: EngineInterface): Promise<void> {
	try {
		const [name, tag] = await Promise.all([$.env.get("HCOM_NAME"), $.env.get("HCOM_TAG")]);

		if (!name || !tag) {
			return;
		}

		const list = await $.process.run(["hcom", "list", "--json", "--name", name], { timeoutMs: 1500 });

		if (list.exitCode !== 0 || list.isStdoutTruncated) {
			return;
		}

		const agents = parseAgents(list.stdout);

		if (!deriveTeam(agents, [], name, tag, Date.now())) {
			return;
		}

		const history = await $.process.run(["hcom", "events", "--full", "--type", "message", "--participant", name, "--last", String(MAX_HCOM_EVENTS), "--name", name], { timeoutMs: 1500 });

		if (history.exitCode !== 0 || history.isStdoutTruncated) {
			return;
		}

		const historyEvents = parseEvents(history.stdout);

		hcomState = {
			agents,
			messages: keepSessionMessages(historyEvents.messages, name, MAX_HCOM_EVENTS),
			name,
			tag,
			statusFetchedAt: Date.now(),
			lastId: historyEvents.lastId,
		};
		$.ui.invalidate("ui.render");
		await observeHcom($);
	} catch {
		hcomState = null;
		$.ui.invalidate("ui.render");
	}
}

/**
 * Keep the team rows current by waiting for new HCOM events, then rereading teammate statuses.
 *
 * This polls `hcom events --wait` because `hcom events sub` posts notices into this session's
 * conversation. The host stops a running wait when this module unloads.
 *
 * @param  {EngineInterface}  $
 *     The host services for this session.
 */
async function observeHcom($: EngineInterface): Promise<void> {
	let previousWaitStartedAt = 0;

	while (hcomState) {
		// Leave at least a second between waits, so an HCOM that keeps returning at once cannot make this loop spin.
		const delay = 1000 - (Date.now() - previousWaitStartedAt);

		if (delay > 0) {
			await new Promise<void>(resolve => {
				$.clock.after(delay, resolve);
			});
		}

		if (!hcomState) {
			break;
		}

		previousWaitStartedAt = Date.now();

		try {
			const output: string[] = [];
			let exitCode: number | null = 0;
			const argv = hcomWaitArgv(hcomState.lastId, hcomState.name, MAX_HCOM_EVENTS);

			for await (const piece of $.process.spawn({ argv })) {
				if ("text" in piece && piece.stream === "stdout") {
					output.push(piece.text);
				}

				if ("code" in piece) {
					exitCode = piece.code;
				}
			}

			const response = output.join("").trim();

			// A wait that finds nothing new exits with code 1. Redraw anyway so the status ages keep counting.
			if (exitCode === 1 && (response === "" || response === '{"timed_out":true}')) {
				$.ui.invalidate("ui.render");
				continue;
			}

			if (exitCode !== 0 || !hcomState) {
				continue;
			}

			const events = parseEvents(response);
			const list = await $.process.run(["hcom", "list", "--json", "--name", hcomState.name], { timeoutMs: 1500 });

			if (list.exitCode !== 0 || list.isStdoutTruncated) {
				continue;
			}

			const agents = parseAgents(list.stdout);
			const messages = keepSessionMessages([...hcomState.messages, ...events.messages], hcomState.name, MAX_HCOM_EVENTS);

			hcomState.agents = agents;
			hcomState.messages = messages;
			hcomState.statusFetchedAt = Date.now();
			hcomState.lastId = Math.max(hcomState.lastId, events.lastId);
			$.ui.invalidate("ui.render");
		} catch {
			// A later HCOM read can fail without losing the last team snapshot or event cursor.
			continue;
		}
	}
}

/**
 * Read the teammate fields from HCOM's JSON agent list.
 *
 * @param  {string}  output
 *     The completed `hcom list --json` output.
 */
function parseAgents(output: string): HcomPeer[] {
	const value: unknown = JSON.parse(output);

	if (!Array.isArray(value)) {
		return [];
	}

	return value.filter((agent): agent is HcomPeer => agent !== null && typeof agent === "object" &&
		typeof agent.name === "string" && typeof agent.tag === "string" &&
		typeof agent.status === "string" && typeof agent.status_age_seconds === "number");
}

/**
 * Read HCOM event lines into the messages this band needs and the highest event ID seen. Malformed lines, and messages missing a needed field, are skipped.
 *
 * @param  {string}  output
 *     The completed `hcom events --full` output.
 */
function parseEvents(output: string): { messages: HcomMessage[]; lastId: number } {
	const messages: HcomMessage[] = [];
	let lastId = 0;

	for (const line of output.split("\n")) {
		if (!line.trim()) {
			continue;
		}

		let value: unknown;

		try {
			value = JSON.parse(line);
		} catch {
			continue;
		}

		if (value === null || typeof value !== "object") {
			continue;
		}

		const event = value as Record<string, unknown>;

		if (typeof event.ts !== "string" || !Number.isFinite(Date.parse(event.ts)) ||
			typeof event.id !== "number" || !Number.isSafeInteger(event.id)) {
			continue;
		}

		lastId = Math.max(lastId, event.id);

		if (event.type !== "message" || event.data === null || typeof event.data !== "object") {
			continue;
		}

		const data = event.data as Record<string, unknown>;

		if (typeof data.from !== "string" || !Array.isArray(data.delivered_to) ||
			!data.delivered_to.every((recipient: unknown) => typeof recipient === "string") ||
			typeof data.intent !== "string" || typeof data.text !== "string") {
			continue;
		}

		messages.push({
			id: String(event.id),
			ts: event.ts,
			from: data.from,
			delivered_to: data.delivered_to,
			intent: data.intent,
			...(typeof data.reply_to === "string" || typeof data.reply_to === "number" ? { reply_to: String(data.reply_to) } : {}),
			text: data.text,
		});
	}

	return { messages, lastId };
}

/**
 * Find the most recently started in-progress task and its active chunk.
 *
 * Returns null, which hides the task row, when nothing is in progress or `progress` fails or is slow.
 *
 * @param  {EngineInterface}  $
 *     The host services for this render.
 */
async function loadTask($: EngineInterface): Promise<TaskLine | null> {
	try {
		const tasksResult = await $.process.run(["progress", "task", "list", "--status", "in-progress", "--all", "--json"], { timeoutMs: 1500 });

		if (tasksResult.exitCode !== 0 || tasksResult.isStdoutTruncated) {
			return null;
		}

		const tasks = JSON.parse(tasksResult.stdout) as { data?: { items?: unknown[] } };
		const activeTasks = tasks.data?.items?.filter(isTask) ?? [];

		activeTasks.sort((first, second) => Date.parse(second.started_at) - Date.parse(first.started_at));

		const [latest] = activeTasks;

		if (!latest) {
			return null;
		}

		const chunksResult = await $.process.run(["progress", "chunk", "list", "--task", latest.id, "--all", "--json"], { timeoutMs: 1500 });

		if (chunksResult.exitCode !== 0 || chunksResult.isStdoutTruncated) {
			return null;
		}

		const chunks = JSON.parse(chunksResult.stdout) as { data?: { items?: unknown[] } };
		const items = chunks.data?.items?.filter(isChunk) ?? [];
		const active = items.find(chunk => chunk.status === "active");

		return {
			title: latest.title,
			more: activeTasks.length - 1,
			...(active ? { chunk: { title: active.title, position: active.position, total: items.length } } : {}),
		};
	} catch {
		return null;
	}
}

/**
 * Check that a task from `progress` has the fields the task row needs.
 *
 * @param  {unknown}  value
 *     One item from the task list.
 */
function isTask(value: unknown): value is { id: string; title: string; started_at: string } {
	return value !== null && typeof value === "object" &&
		typeof (value as Record<string, unknown>).id === "string" &&
		typeof (value as Record<string, unknown>).title === "string" &&
		typeof (value as Record<string, unknown>).started_at === "string";
}

/**
 * Check that a chunk from `progress` has the fields the task row needs.
 *
 * @param  {unknown}  value
 *     One item from the chunk list.
 */
function isChunk(value: unknown): value is { title: string; position: number; status: string } {
	return value !== null && typeof value === "object" &&
		typeof (value as Record<string, unknown>).title === "string" &&
		typeof (value as Record<string, unknown>).position === "number" &&
		typeof (value as Record<string, unknown>).status === "string";
}

/**
 * Read how many tool calls the checkpoint hook has counted for this session.
 *
 * Returns null when the hook keeps no count, such as outside an HCOM team, and 0 when the file holds something
 * other than a number. The band only reads this file; the hook owns it.
 *
 * @param  {EngineInterface}  $
 *     The host services for this render.
 */
async function readCalls($: EngineInterface): Promise<number | null> {
	try {
		const sessionId = await $.session.id();

		if (!/^[A-Za-z0-9._-]+$/.test(sessionId)) {
			return null;
		}

		const temporaryDirectory = await $.env.get("TMPDIR") || "/tmp";
		const path = `${temporaryDirectory.replace(/\/$/, "")}/agent-tool-call-checkpoints/claude-${sessionId}`;
		const count = (await $.fs.read(path)).trim();

		return /^[0-9]+$/.test(count) && Number.isSafeInteger(Number(count)) ? Number(count) : 0;
	} catch {
		return null;
	}
}

/**
 * Look up this session's tool-call limit from the same settings the checkpoint hook reads.
 *
 * @param  {EngineInterface}  $
 *     The host services for this render.
 */
async function loadLimit($: EngineInterface): Promise<number> {
	const [tag, override] = await Promise.all([$.env.get("HCOM_TAG"), $.env.get("AGENT_TOOL_CALL_LIMIT")]);

	return checkpointLimit(tag, override);
}
