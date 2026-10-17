// The status band keeps no session state.
declare module "claude-code" {
	interface PluginState {
		"status-band": Record<string, never>;
	}
}
