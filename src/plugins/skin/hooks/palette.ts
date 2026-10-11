/** The colours the skin uses for the rows it draws itself. */
type Palette = {
	/** The tool name and the footer's diamond. */
	accent: string;
	/** The rounded border around Bash output. */
	border: string;
	/** The status dot of a tool call that finished. */
	done: string;
	/** The status dot of a tool call that failed. */
	failed: string;
	/** The tool header's summary and the footer text. */
	muted: string;
	/** The status dot of a tool call that is still running. */
	running: string;
};

/** Catppuccin Mocha for dark backgrounds and Latte for light ones. */
export const palettes = {
	mocha: {
		accent: "#cba6f7",
		border: "#585b70",
		done: "#a6e3a1",
		failed: "#f38ba8",
		muted: "#a6adc8",
		running: "#f9e2af",
	},
	latte: {
		accent: "#8839ef",
		border: "#9ca0b0",
		done: "#40a02b",
		failed: "#d20f39",
		muted: "#6c6f85",
		running: "#df8e1d",
	},
} as const satisfies Record<string, Palette>;

/**
 * Pick Latte for a light background and Mocha otherwise.
 *
 * @param  {unknown}  theme
 *     The user's Claude Code theme setting, such as `light` or `dark-ansi`. It wins when it names light or dark.
 * @param  {string|undefined}  colourHint
 *     The terminal's `COLORFGBG` value, `<foreground>;<background>`, used when the theme doesn't say.
 *     A background of 7 or 15 (white) means a light terminal.
 */
export function paletteFor(theme: unknown, colourHint: string | undefined) {
	if (typeof theme === "string" && /light|latte/i.test(theme)) {
		return palettes.latte;
	}

	if (typeof theme === "string" && /dark|mocha/i.test(theme)) {
		return palettes.mocha;
	}

	const background = colourHint?.split(";").at(-1);

	return background === "7" || background === "15" ? palettes.latte : palettes.mocha;
}
