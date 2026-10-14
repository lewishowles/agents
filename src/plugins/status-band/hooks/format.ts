/** The task row's content: the newest in-progress task and its active chunk. */
export type TaskLine = {
	/** The title of the most recently started in-progress task. */
	title: string;
	/** How many other tasks are in progress, shown as "+N more". */
	more: number;
	/** The task's active chunk, with its position among all of the task's chunks. */
	chunk?: { title: string; position: number; total: number };
};

/** The task title's share of free space when both titles need shortening. */
const TASK_TITLE_SHARE = 0.45;

/** Tool calls remaining when the band starts warning about a checkpoint. */
export const CHECKPOINT_WARNING_REMAINING = 3;

/**
 * Fit a row into the given number of columns, collapsing runs of whitespace and ending with an ellipsis when the text is cut.
 *
 * @param  {string}  value
 *     The row to show.
 * @param  {number}  columns
 *     The number of columns available to the row.
 */
export function truncateLine(value: string, columns: number): string {
	const text = value.replace(/\s+/g, " ").trim();
	const characters = Array.from(text);

	if (characters.length <= columns) {
		return text;
	}

	return columns > 1 ? `${characters.slice(0, columns - 1).join("")}…` : "…";
}

/**
 * Build the task row: the newest in-progress task, a count of any others, and its active chunk.
 *
 * When both titles are too long to fit, the task title gets at most 45% of the free space and the chunk title gets the rest.
 *
 * @param  {TaskLine}  task
 *     The selected task and optional active chunk.
 * @param  {number}  columns
 *     The available row width.
 */
export function formatTaskLine(task: TaskLine, columns: number): string {
	const prefix = "Task: ";
	const more = task.more > 0 ? ` +${task.more} more` : "";
	const chunkPrefix = task.chunk ? ` · chunk ${task.chunk.position}/${task.chunk.total}: ` : "";
	const available = columns - prefix.length - more.length - chunkPrefix.length;

	if (available < 2) {
		return truncateLine(`${prefix}${task.title}${more}${chunkPrefix}${task.chunk?.title ?? ""}`, columns);
	}

	const title = task.title.replace(/\s+/g, " ").trim();
	const chunkTitle = task.chunk?.title.replace(/\s+/g, " ").trim() ?? "";
	const titleBudget = task.chunk
		? Math.min(Array.from(title).length, Math.max(Math.floor(available * TASK_TITLE_SHARE), available - Array.from(chunkTitle).length))
		: available;
	const chunkBudget = available - titleBudget;
	const taskTitle = truncateLine(title, titleBudget);
	const activeChunk = task.chunk ? `${chunkPrefix}${truncateLine(chunkTitle, chunkBudget)}` : "";

	return truncateLine(`${prefix}${taskTitle}${more}${activeChunk}`, columns);
}

/**
 * Return the tool-call limit the checkpoint hook applies to this session.
 *
 * A positive whole-number override wins, then 40 for Scout and Implementer roles, then 20. Keep this in step with
 * `resolve_tool_call_limit` in src/hooks/shared/tool-call-checkpoint.sh.
 *
 * @param  {string|undefined}  tag
 *     The HCOM role tag, when this session has one.
 * @param  {string|undefined}  override
 *     The AGENT_TOOL_CALL_LIMIT value, when it is set.
 */
export function checkpointLimit(tag: string | undefined, override: string | undefined): number {
	if (override && /^[1-9][0-9]*$/.test(override)) {
		return Number(override);
	}

	return /(^|-)(scout|implementer)$/.test(tag ?? "") ? 40 : 20;
}

/**
 * Build the meter row: how full the context window is and, when the session is counted, the tool calls used.
 *
 * The row says "checkpoint soon" during the final three calls and "checkpoint reached" at the limit.
 *
 * @param  {object}  context
 *     The host's context figures: a percentage when known, otherwise a token count.
 * @param  {number|null}  calls
 *     The checkpoint hook's count, or null when the hook keeps no count for this session.
 * @param  {number}  limit
 *     The checkpoint hook's limit for this role.
 * @param  {number}  columns
 *     The available row width.
 */
export function formatMeter(context: { percent?: number; tokens?: number }, calls: number | null, limit: number, columns: number): string {
	const filled = Math.round((context.percent ?? 0) / 10);
	const bar = `${"█".repeat(filled)}${"░".repeat(10 - filled)}`;
	let contextText = "Context pending";

	if (context.percent !== undefined) {
		contextText = `Context ${context.percent}% [${bar}]`;
	} else if (context.tokens !== undefined) {
		contextText = `Context ${context.tokens.toLocaleString("en-GB")} tokens`;
	}

	if (calls === null) {
		return truncateLine(contextText, columns);
	}

	let warning = "";

	if (calls >= limit) {
		warning = " · checkpoint reached";
	} else if (calls >= limit - CHECKPOINT_WARNING_REMAINING) {
		warning = " · checkpoint soon";
	}

	return truncateLine(`${contextText} · tools ${calls}/${limit}${warning}`, columns);
}
