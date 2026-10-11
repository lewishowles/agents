/** Session state owned by the skin plugin. */
declare module "claude-code" {
	interface PluginState {
		skin: {
			/** Tool calls in the current main turn. */
			toolCount: number;
			/** Each finished main turn's tool count, keyed by the turn's length in milliseconds. */
			footerCounts: Record<string, number>;
			/** The palette picked for this session, or null before it has been picked. */
			paletteName: "mocha" | "latte" | null;
		};
	}
}
