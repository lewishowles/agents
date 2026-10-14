import type { EngineInterface, Register } from "claude-code";

import { CHECKPOINT_WARNING_REMAINING, checkpointLimit, formatMeter, formatTaskLine } from "./format";
import type { TaskLine } from "./format";

/** The widest a band row may be, so that it stays under 90 columns in narrow terminal panes. */
const MAX_COLUMNS = 89;

/** Draw the task and meter rows above the prompt, and redraw them after each tool call and turn. */
export const register: Register = on => {
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
		const earlierBand = await next(event);

		// Claude Code refuses to draw its own band content inside a Box that sets a width, so the formatters keep
		// each row within the width instead.
		return (
			<Box flexDirection="column">
				{task && <Text wrap="truncate-end" color="subtle">{formatTaskLine(task, columns)}</Text>}
				<Text wrap="truncate-end" color={calls !== null && calls >= limit - CHECKPOINT_WARNING_REMAINING ? "warning" : "subtle"}>{meter}</Text>
				{earlierBand}
			</Box>
		);
	});
};

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
