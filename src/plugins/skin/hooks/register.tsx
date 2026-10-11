import { atom, read, update } from "claude-code";
import type { EngineInterface, Register } from "claude-code";

import { paletteFor, palettes } from "./palette";

/** The number of tool calls in the current main turn, failed ones included, for the footer. */
const toolCount = atom({ plugin: "skin", key: "toolCount" } as const, 0);

/**
 * The tool count of each finished main turn, so older footers keep their own number. Footers carry no turn ID,
 * so turns are keyed by their length in milliseconds; two turns of exactly the same length share an entry.
 */
const footerCounts = atom({ plugin: "skin", key: "footerCounts" } as const, {} as Record<string, number>);

/** The palette picked when the session started, or null until it has been picked. */
const paletteName = atom({ plugin: "skin", key: "paletteName" } as const, null as "mocha" | "latte" | null);

/** Register the skin's tool headers, boxed Bash output, and turn footer. */
export const register: Register = on => {
	on("session.start", async ($, event, next) => {
		const selected = await resolvePaletteName($);

		await update($, paletteName, () => selected);

		return next(event);
	});

	on("turn.start", async ($, event, next) => {
		await update($, toolCount, () => 0);

		return next(event);
	});

	on("tool.call", async ($, event, next) => {
		if (event.agentId === undefined) {
			await update($, toolCount, count => count + 1);
		}

		return next(event);
	});

	on("turn.complete", async ($, event, next) => {
		if (event.agentId === undefined) {
			const count = await read($, toolCount);

			await update($, footerCounts, counts => ({ ...counts, [String(event.durationMs)]: count }));
		}

		return next(event);
	});

	// Replaces Claude Code's tool header with a `●─ Tool  summary` line whose dot shows the call's status.
	on("ui.render", { component: "ToolUse" }, async ($, event) => {
		const { Box, Text } = $.ui.resolve(event);
		const palette = await activePalette($);
		const { input, isErrored, isInterrupted, isRunning, tool } = event.props;
		const fields = input !== null && typeof input === "object" ? input as Record<string, unknown> : {};
		const summary = toolSummary(fields);
		const status = isRunning ? palette.running : isInterrupted ? palette.muted : isErrored ? palette.failed : palette.done;

		return (
			<Box marginTop={1}>
				<Text wrap="truncate-end">
					<Text color={status}>●─ </Text>
					<Text color={palette.accent} bold>{tool}</Text>
					{summary && <Text color={palette.muted}>{`  ${summary}`}</Text>}
					{isInterrupted && <Text color={palette.muted}> interrupted</Text>}
				</Text>
			</Box>
		);
	});

	// Keeps Claude Code's own Bash output and draws a border around it. Other tools' results are left alone.
	on("ui.render", { component: "ToolResult" }, async ($, event, next) => {
		if (event.props.tool !== "Bash") {
			return next(event);
		}

		const { Box } = $.ui.resolve(event);
		const palette = await activePalette($);

		return <Box borderStyle="round" borderColor={palette.border} paddingX={1}>{await next(event)}</Box>;
	});

	// Replaces the closing line of a turn with `◆ Done in <duration> · <N> tools`.
	on("ui.render", { component: "TurnDuration" }, async ($, event) => {
		const { Box, Text } = $.ui.resolve(event);
		const palette = await activePalette($);
		const counts = await read($, footerCounts);
		const count = counts[String(event.props.durationMs)] ?? await read($, toolCount);
		const tools = count === 1 ? "tool" : "tools";

		return (
			<Box marginTop={1}>
				<Text color={palette.accent}>◆ </Text>
				<Text color={palette.muted}>{`Done in ${formatDuration(event.props.durationMs)} · ${count} ${tools}`}</Text>
			</Box>
		);
	});
};

/**
 * Find what a tool call is acting on, for its header: the first non-empty command, path, pattern, query, address
 * or description, on one line.
 *
 * @param  {Record<string, unknown>}  fields
 *     The tool call's input. Returns an empty string when none of the fields is a non-empty string.
 */
function toolSummary(fields: Record<string, unknown>): string {
	for (const key of ["command", "file_path", "notebook_path", "path", "pattern", "query", "url", "description"]) {
		const value = fields[key];

		if (typeof value === "string" && value.trim()) {
			return value.replace(/\s+/g, " ").trim();
		}
	}

	return "";
}

/**
 * Format a turn's length for the footer, such as `41s` or `2m 5s`.
 *
 * @param  {number}  durationMs
 *     The turn's length in milliseconds.
 */
function formatDuration(durationMs: number): string {
	const seconds = Math.round(durationMs / 1000);
	const minutes = Math.floor(seconds / 60);
	const remainder = seconds % 60;

	return minutes > 0 ? `${minutes}m ${remainder}s` : `${seconds}s`;
}

/**
 * Get the session's palette, picking it now if the session started before the skin loaded.
 *
 * @param  {EngineInterface}  $
 *     The engine for the current hook.
 */
async function activePalette($: EngineInterface) {
	const selected = await read($, paletteName);

	if (selected !== null) {
		return palettes[selected];
	}

	return palettes[await resolvePaletteName($)];
}

/**
 * Pick Latte or Mocha from the user's Claude Code theme setting and the terminal's background.
 *
 * @param  {EngineInterface}  $
 *     The engine for the current hook.
 */
async function resolvePaletteName($: EngineInterface): Promise<"mocha" | "latte"> {
	const theme = (await $.config.list()).find(row => row.key === "theme")?.value;
	const colourHint = await $.env.get("COLORFGBG");

	return paletteFor(theme, colourHint) === palettes.latte ? "latte" : "mocha";
}
