// The task row's content: the newest in-progress task and its active chunk.
export type TaskLine = {
	// The title of the most recently started in-progress task.
	title: string;
	// How many other tasks are in progress, shown as "+N more".
	more: number;
	// The task's active chunk, with its position among all of the task's chunks.
	chunk?: { title: string; position: number; total: number };
};

// A teammate shown in the HCOM row.
export type PeerLine = {
	// The teammate's role in this team.
	role: string;
	// The teammate's current HCOM status.
	status: string;
	// Seconds since HCOM last changed that status.
	ageSeconds: number;
	// Seconds since this session asked for a reply, when one is outstanding.
	waitSeconds?: number;
};

// The HCOM fields needed to identify a teammate and show their status.
export type HcomPeer = {
	// The agent's full name, used to match short names in messages.
	name: string;
	// The team and role assigned when the agent was launched.
	tag: string;
	// The current HCOM activity state.
	status: string;
	// Seconds since HCOM last changed that state.
	status_age_seconds: number;
};

// The HCOM message fields needed to find replies and stopped teammates.
export type HcomMessage = {
	// The event ID that replies refer to.
	id: string;
	// The event time used to order messages and show wait ages.
	ts: string;
	// The sender's short or full HCOM name.
	from: string;
	// The agents who received the message.
	delivered_to: string[];
	// Request, inform, or ack; only a request expects a reply.
	intent: string;
	// The message ID this message continues or answers, when present.
	reply_to?: string;
	// The message body, checked for `human decision required`.
	text: string;
};

// The rows derived from one team's current HCOM records.
export type TeamLine = {
	// Teammates and any pending waits for the peer row.
	peers: PeerLine[];
	// Roles of teammates that have stopped and are waiting for the human to continue or reset them.
	checkpoints: string[];
};

// The task title's share of free space when both titles need shortening.
const TASK_TITLE_SHARE = 0.45;

// Tool calls remaining when the band starts warning about a checkpoint.
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

/**
 * Show each teammate's role, current status, and time in that status.
 *
 * @param  {PeerLine[]}  peers
 *     Teammates in this HCOM team, excluding this session.
 * @param  {number}  columns
 *     The available row width.
 */
export function formatPeers(peers: PeerLine[], columns: number): string {
	const entries = peers.map(peer => {
		const age = formatAge(peer.ageSeconds);
		const wait = peer.waitSeconds === undefined ? "" : ` (waiting ${formatAge(peer.waitSeconds)})`;

		return `${peer.role} ${peer.status} ${age}${wait}`;
	});

	return truncateLine(`Peers: ${entries.join(" · ")}`, columns);
}

/**
 * Ask whether to continue or reset the stopped teammates, joining several roles as "A, B and C".
 *
 * @param  {string[]}  roles
 *     The roles that still need a decision.
 * @param  {number}  columns
 *     The available row width.
 */
export function formatCheckpoint(roles: string[], columns: number): string {
	const capitalisedRoles = roles.map(role => `${role.charAt(0).toUpperCase()}${role.slice(1)}`);
	const lastRole = capitalisedRoles.at(-1);
	const leadingRoles = capitalisedRoles.slice(0, -1);
	const names = leadingRoles.length > 0 ? `${leadingRoles.join(", ")} and ${lastRole}` : lastRole;

	return truncateLine(`${names} stopped: continue or reset?`, columns);
}

/**
 * Build the command that waits for HCOM events newer than the last one read.
 *
 * It filters by event ID because `--after` also returns an event at exactly the given time.
 *
 * @param  {number}  lastId
 *     The highest HCOM event ID already read.
 * @param  {string}  name
 *     This session's HCOM name.
 * @param  {number}  limit
 *     The maximum events returned by one wait.
 */
export function hcomWaitArgv(lastId: number, name: string, limit: number): string[] {
	return ["hcom", "events", "--full", "--sql", `id > ${lastId}`, "--wait", "30", "--last", String(limit), "--name", name];
}

/**
 * Keep the newest messages sent by or to this session, once each, up to the limit.
 *
 * @param  {HcomMessage[]}  messages
 *     Previously kept messages followed by newly read messages.
 * @param  {string}  name
 *     This session's short or full HCOM name.
 * @param  {number}  limit
 *     The most messages to keep.
 */
export function keepSessionMessages(messages: HcomMessage[], name: string, limit: number): HcomMessage[] {
	const relevant = messages.filter(message =>
		matchesName(name, message.from) ||
		message.delivered_to.some(recipient => matchesName(name, recipient)));
	const seen = new Set<string>();
	const unique = relevant.filter(message => {
		if (seen.has(message.id)) {
			return false;
		}

		seen.add(message.id);
		return true;
	});

	return unique.slice(-limit);
}

/**
 * Select this session's teammates, find which of this session's requests are still unanswered, and find which teammates have stopped.
 *
 * Returns null when the HCOM identity does not resolve to exactly one agent in the team.
 *
 * @param  {HcomPeer[]}  agents
 *     Agents currently listed by HCOM.
 * @param  {HcomMessage[]}  messages
 *     Messages to and from this session, in any order.
 * @param  {string}  name
 *     This session's HCOM_NAME, which may be a short instance name.
 * @param  {string}  tag
 *     This session's full team and role tag.
 * @param  {number}  now
 *     The current time in milliseconds, used to show wait ages.
 * @param  {number}  ageOffsetSeconds
 *     The seconds since the agent statuses were fetched, added to each status age.
 */
export function deriveTeam(agents: HcomPeer[], messages: HcomMessage[], name: string, tag: string, now: number, ageOffsetSeconds = 0): TeamLine | null {
	const separator = tag.lastIndexOf("-");

	if (separator < 1) {
		return null;
	}

	const team = tag.slice(0, separator);
	// Keep only agents whose tag is this team plus one role word, so a labelled sub-team is not mixed in.
	const members = agents.filter(agent => agent.tag.startsWith(`${team}-`) && !agent.tag.slice(team.length + 1).includes("-"));
	const matches = members.filter(agent => agent.tag === tag && matchesName(agent.name, name));

	const self = matches[0];

	if (matches.length !== 1 || !self) {
		return null;
	}

	const peers = members.filter(agent => agent.name !== self.name);
	const ordered = [...messages].sort((first, second) => Date.parse(first.ts) - Date.parse(second.ts) || Number(first.id) - Number(second.id));
	const lines: PeerLine[] = [];
	const checkpoints: string[] = [];

	for (const peer of peers) {
		const role = peer.tag.slice(team.length + 1);
		// Find this session's requests to the peer that the peer has not yet answered with a reply sent back to this session.
		const openRequests = ordered.filter((message, index) =>
			matchesName(self.name, message.from) && message.intent === "request" &&
			message.delivered_to.some(recipient => matchesName(peer.name, recipient)) &&
			!ordered.slice(index + 1).some(reply => reply.reply_to === message.id &&
				matchesName(peer.name, reply.from) &&
				reply.delivered_to.some(recipient => matchesName(self.name, recipient))));
		const oldestRequest = openRequests[0];
		const waitSeconds = oldestRequest ? Math.max(0, Math.floor((now - Date.parse(oldestRequest.ts)) / 1000)) : undefined;

		lines.push({
			role,
			status: peer.status,
			ageSeconds: Math.max(0, peer.status_age_seconds + ageOffsetSeconds),
			...(waitSeconds === undefined ? {} : { waitSeconds }),
		});

		const lastIncoming = ordered.findLastIndex(message =>
			matchesName(peer.name, message.from) &&
			message.delivered_to.some(recipient => matchesName(self.name, recipient)));
		const incomingMessage = ordered[lastIncoming];

		if (!incomingMessage?.text.includes("human decision required")) {
			continue;
		}

		const answered = ordered.slice(lastIncoming + 1).some(message =>
			matchesName(self.name, message.from) &&
			message.delivered_to.some(recipient => matchesName(peer.name, recipient)));

		if (!answered) {
			checkpoints.push(role);
		}
	}

	return { peers: lines, checkpoints };
}

/**
 * Check whether two HCOM names refer to the same agent, where either may be the short instance name that ends the full name.
 *
 * @param  {string}  firstName
 *     The first HCOM name to compare.
 * @param  {string}  secondName
 *     The second HCOM name to compare.
 */
export function matchesName(firstName: string, secondName: string): boolean {
	return firstName === secondName || firstName.endsWith(`-${secondName}`) || secondName.endsWith(`-${firstName}`);
}

/**
 * Show elapsed time as whole seconds, minutes, or hours, so it fits a narrow terminal pane.
 *
 * @param  {number}  seconds
 *     The non-negative elapsed time reported by HCOM or calculated from a message.
 */
function formatAge(seconds: number): string {
	if (seconds < 60) {
		return `${Math.floor(seconds)}s`;
	}

	if (seconds < 3600) {
		return `${Math.floor(seconds / 60)}m`;
	}

	return `${Math.floor(seconds / 3600)}h`;
}
