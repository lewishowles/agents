# Orchestrator status band

This Claude Code mod shows the current progress task, context use, and tool-call count above the prompt. The task line disappears when no task is in progress or progress cannot be read. In HCOM team sessions, the meter shows tool calls against the session's checkpoint limit.

In an HCOM team, a peer row shows each teammate's role, status, and time in that status. It marks requests still waiting for a reply. When a teammate's latest message says `human decision required`, a warning asks `<Role> stopped: continue or reset?` until this session sends them another message. The rows stay hidden if the first HCOM read fails or the team identity cannot be read.

Try it from this repository with `claude --plugin-dir src/plugins/status-band`. The band fits within 90 columns and cuts long titles short. It reads the checkpoint counter written by the shared shell hook; the hook still decides when a checkpoint fires.
