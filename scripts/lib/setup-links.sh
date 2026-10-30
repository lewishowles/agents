#!/usr/bin/env bash
# Shared symlink and backup helpers for setup scripts.

# Produces a timestamp string used to make backup filenames unique.
timestamp() {
	date '+%Y%m%d-%H%M%S'
}

# Moves a file to a timestamped backup location and prints the backup path.
# Backup paths are routed by prefix so each agent's backups stay separate.
# Only one backup is kept per source path; older ones are removed first so
# setup runs don't leave a growing pile of stale backups behind.
#
# @param  {string}  path
#     The file or symlink to back up.
backup_path() {
	# The file or symlink to back up.
	local path="$1"
	# The folder that holds backups for this kind of path.
	local backup_dir

	backup_dir=$(backup_dir_for_path "$path")

	# The original filename, used to find older backups of the same path.
	local backup_base
	backup_base="$(basename "$path")"
	mkdir -p "$backup_dir"

	# An older backup of the same path, to remove.
	local old
	while IFS= read -r old; do
		trash "$old"
	done < <(find "$backup_dir" -maxdepth 1 -name "${backup_base}.bak.*" 2>/dev/null)

	# The timestamped path the file or symlink moves to.
	local backup
	backup="$backup_dir/${backup_base}.bak.$(timestamp)"
	mv "$path" "$backup"
	printf '%s' "$backup"
}

# Prints the folder that holds a path's timestamped backups.
#
# @param  {string}  path
#     The path setup may replace.
backup_dir_for_path() {
	# The path whose location decides the backup folder.
	local path="$1"

	case "$path" in
		"$HOME"/.claude*/skills/*)   printf '%s' "$(dirname "$(dirname "$path")")/backups/skills" ;;
		"$HOME"/.claude*/hooks/*)    printf '%s' "$(dirname "$(dirname "$path")")/backups/hooks" ;;
		"$HOME"/.claude*/themes/*)   printf '%s' "$(dirname "$(dirname "$path")")/backups/themes" ;;
		"$HOME/.agents/skills/"*)    printf '%s' "$HOME/.agents/backups/skills" ;;
		*)                           dirname "$path" ;;
	esac
}

# Prints a path with $HOME replaced by ~ for readable terminal output.
#
# @param  {string}  path
#     The absolute path to display.
display_path() {
	# The absolute path to shorten for terminal output.
	local path="$1"

	# The ~ is printed as text on purpose, to shorten home paths in the output.
	# shellcheck disable=SC2088
	case "$path" in
		"$HOME"/*) printf '~/%s' "${path#"$HOME"/}" ;;
		*) printf '%s' "$path" ;;
	esac
}

# Ensures a directory exists as a real directory, not a symlink.
# Per-item symlinks inside the directory need the parent to be a real dir.
#
# @param  {string}  path
#     The directory path to ensure.
# @param  {string}  label
#     Human-readable name for output messages.
ensure_container_dir() {
	# The path that must be a real directory rather than a file or symlink.
	local path="$1"
	# The readable name used when reporting a replacement.
	local label="$2"

	if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
		# The backup path for the file or symlink being replaced.
		local backup
		backup=$(backup_path "$path")
		mkdir -p "$path"
		cli_group_status warning "replaced $label" "backup at $(display_path "$backup")"
	else
		mkdir -p "$path"
	fi
}

# Removes stale or repo-owned symlinks in a directory.
# Symlinks pointing elsewhere are left alone.
#
# @param  {string}  dir
#     Directory to scan.
# @param  {string}  repo_prefix
#     Only prune links whose target starts with this path.
# @param  {string}  label
#     Human-readable name used in output messages.
# @param  {string}  remove_all
#     Set to 1 to remove all repo-owned links, including valid links.
prune_stale_repo_links() {
	# The folder whose symlinks are checked for removal.
	local dir="$1"
	# The path prefix that identifies links pointing into this repository.
	local repo_prefix="$2"
	# The readable folder name used in removal messages.
	local label="$3"
	# Whether to remove working repository links as well as broken ones (1 to remove them).
	local remove_all="${4:-0}"

	[ -d "$dir" ] || return 0

	# The installed link being checked, and the path it points to.
	local link target
	for link in "$dir"/*; do
		[ -L "$link" ] || continue
		target=$(readlink "$link")
		if [[ "$target" == "$repo_prefix"* ]] && {
			[ "$remove_all" = "1" ] || [ ! -e "$link" ]
		}; then
			trash "$link"
			if [ "$remove_all" = "1" ]; then
				cli_group_status warning "removed repo-owned" "$label/$(basename "$link")"
			else
				cli_group_status warning "removed stale" "$label/$(basename "$link")"
			fi
		fi
	done
}

# Returns 0 only when the target is a symlink whose link text is the expected
# canonical source path. Comparing link text preserves a link to the same
# checkout through another path form instead of replacing it.
#
# @param  {string}  source
#     The canonical path that the target must name.
# @param  {string}  target
#     The installed skill path being checked.
is_repo_owned_link() {
	# Canonical path that a managed link must name.
	local source="$1"
	# Installed link path being checked.
	local target="$2"
	# Link text currently stored at the installed path.
	local current

	if [ ! -L "$target" ]; then
		return 1
	fi

	current=$(readlink "$target")
	[ "$current" = "$source" ]
}

# Calls a function once for each link in one group of repository links, apart
# from skills, giving it the repository file, the installed path and the label
# to show. This is the only place those links are listed: the setup preview,
# the installer and the doctor all read them from here, and each caller decides
# which groups the chosen features need.
#
# @param  {string}  agent
#     The agent whose links are listed: claude, codex, or shared for the trash
#     wrapper.
# @param  {string}  group
#     The group to list: core, settings, hooks, themes, rules, manifest or
#     trash.
# @param  {string}  callback
#     The function to call with the source, target and label of each link.
managed_links() {
	# The agent and group whose links are listed.
	local agent="$1" group="$2"
	# The function called with each link.
	local callback="$3"
	# The generated file currently listed, and its installed filename.
	local source name
	# The directory receiving hook links, and the extension for themes or rules.
	local target_dir extension

	case "$agent:$group" in
		claude:core)
			for name in CLAUDE.md .mcp.json statusline.sh; do
				"$callback" "$REPO_DIR/dist/claude/$name" "$CLAUDE_DIR/$name" "$name"
			done
			;;
		claude:settings)
			"$callback" "$REPO_DIR/dist/claude/settings.json" "$CLAUDE_DIR/settings.json" settings.json
			;;
		claude:hooks|codex:hooks)
			if [ "$agent" = claude ]; then
				target_dir="$CLAUDE_DIR/hooks"
			else
				target_dir="$CODEX_DIR/hooks"
			fi
			for source in "$REPO_DIR/dist/$agent/hooks/"*; do
				[ -f "$source" ] || continue
				name=${source##*/}
				"$callback" "$source" "$target_dir/$name" "hooks/$name"
			done
			;;
		claude:themes|claude:rules)
			if [ "$group" = themes ]; then
				extension=json
			else
				extension=md
			fi
			for source in "$REPO_DIR/dist/claude/$group/"*."$extension"; do
				[ -f "$source" ] || continue
				name=${source##*/}
				"$callback" "$source" "$CLAUDE_DIR/$group/$name" "$group/$name"
			done
			;;
		codex:core)
			"$callback" "$REPO_DIR/dist/codex/AGENTS.md" "$HOME/.agents/AGENTS.md" 'global AGENTS.md'
			"$callback" "$REPO_DIR/dist/codex/AGENTS.md" "$CODEX_DIR/AGENTS.md" AGENTS.md
			;;
		codex:manifest)
			"$callback" "$REPO_DIR/dist/codex/hooks.json" "$CODEX_DIR/hooks.json" hooks.json
			;;
		shared:trash)
			"$callback" "$REPO_DIR/src/bin/trash" "$HOME/.local/bin/trash" 'trash wrapper'
			;;
		*)
			return 1
			;;
	esac
}

# Collects each canonical skill directory and rejects duplicate folder names.
# The caller must declare a local skill_paths array before calling this helper.
collect_canonical_skills() {
	# Canonical skill directory currently being collected.
	local skill
	# Skill name taken from the canonical directory basename.
	local slug
	# Previously collected skill directory used for duplicate checks.
	local other
	# Skill name taken from the previously collected directory.
	local other_slug

	skill_paths=()
	for skill in "$REPO_DIR"/skills/*/*; do
		if [ ! -d "$skill" ]; then
			continue
		fi

		slug=${skill##*/}
		if [ "${#skill_paths[@]}" -gt 0 ]; then
			for other in "${skill_paths[@]}"; do
				other_slug=${other##*/}
				if [ "$other_slug" = "$slug" ]; then
					cli_group_status failed "duplicate skill name" "$slug: $(display_path "$other") and $(display_path "$skill")"
					return 1
				fi
			done
		fi

		skill_paths+=("$skill")
	done

	return 0
}

# Creates a symlink from source to target, backing up any conflicting path.
#
# @param  {string}  source
#     The file or directory to link to.
# @param  {string}  target
#     The symlink path to create.
# @param  {string}  label
#     Human-readable name for output messages.
link_path() {
	# The repository file or folder the link should point to.
	local source="$1"
	# The installed path where the symlink should be.
	local target="$2"
	# The readable name used in link status messages.
	local label="$3"

	if is_repo_owned_link "$source" "$target"; then
		cli_group_status muted "$label" "already linked"
		return
	elif [ -L "$target" ]; then
		# The backup path for the symlink being replaced.
		local backup
		backup=$(backup_path "$target")
		ln -s "$source" "$target"
		cli_group_status warning "relinked $label" "backup at $(display_path "$backup")"
	elif [ -e "$target" ]; then
		# The backup path for the file or folder being replaced.
		local backup
		backup=$(backup_path "$target")
		ln -s "$source" "$target"
		cli_group_status warning "replaced $label" "backup at $(display_path "$backup")"
	else
		ln -s "$source" "$target"
		cli_group_status success "linked" "$label"
	fi
}

# Adds a directory creation or replacement to the setup preview.
#
# @param  {string}  path
#     The directory setup will ensure.
plan_container_dir() {
	# The directory setup will create, or replace when something else is there.
	local path="$1"

	if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
		plan_backup "$path"
		plan_change "Directories" "Replace $(display_path "$path") with a directory"
	elif [ ! -d "$path" ]; then
		plan_change "Directories" "Create $(display_path "$path")"
	fi
}

# Adds the backup a replacement will save, and the older backups of the same
# path it will remove, to the setup preview.
#
# @param  {string}  path
#     The existing path that setup will replace.
plan_backup() {
	# The existing path setup will back up.
	local path="$1"
	# The folder that will hold the new backup.
	local backup_dir
	# An older backup of the same path, which backup_path removes.
	local old

	backup_dir=$(backup_dir_for_path "$path")

	if [ -d "$backup_dir" ]; then
		while IFS= read -r old; do
			plan_change "Backups" "Remove older backup $(display_path "$old")"
		done < <(find "$backup_dir" -maxdepth 1 -name "$(basename "$path").bak.*" 2>/dev/null)
	fi

	plan_change "Backups" "Save $(display_path "$path") in $(display_path "$backup_dir") with a timestamp"
}

# Adds a link to the setup preview unless the installed path already points at
# the repository source. Anything else at that path is listed for backup first,
# unless the stale-link cleanup will remove it before linking.
#
# @param  {string}  source
#     The repository file or folder to link.
# @param  {string}  target
#     The path setup will install.
plan_link_path() {
	# The repository file or folder the link should point at.
	local source="$1"
	# The installed path setup will link.
	local target="$2"
	# A link that stale-link cleanup has already listed for removal.
	local pruned_link
	# Whether stale-link cleanup removes the target before it is linked, so
	# there is nothing left to back up.
	local already_pruned=false

	if is_repo_owned_link "$source" "$target"; then
		return
	fi
	if [ -e "$target" ] || [ -L "$target" ]; then
		if [ "${#planned_pruned_links[@]}" -gt 0 ]; then
			for pruned_link in "${planned_pruned_links[@]}"; do
				if [ "$pruned_link" = "$target" ]; then
					already_pruned=true
					break
				fi
			done
		fi
		if [ "$already_pruned" = false ]; then
			plan_backup "$target"
		fi
	fi

	plan_change "Links" "Link $(display_path "$target") to $(display_path "$source")"
}

# Adds the repository links that setup will remove to the setup preview. By
# default only broken links are listed, matching prune_stale_repo_links. Each
# listed link is also added to planned_pruned_links, so plan_link_path does not
# list a backup for it.
#
# @param  {string}  dir
#     The installed link directory to check.
# @param  {string}  repo_prefix
#     The path that repository-owned link targets start with.
# @param  {string}  remove_all
#     Set to 1 to include working links as well as broken ones.
plan_prune_stale_repo_links() {
	# The installed link directory to check.
	local dir="$1"
	# The path that repository-owned link targets start with.
	local repo_prefix="$2"
	# Whether working repository links are removed as well as broken ones.
	local remove_all="${3:-0}"
	# The installed link currently being checked.
	local link
	# The path that link points at.
	local target

	[ -d "$dir" ] || return 0

	for link in "$dir"/*; do
		[ -L "$link" ] || continue
		target=$(readlink "$link")
		if [[ "$target" == "$repo_prefix"* ]] && {
			[ "$remove_all" = 1 ] || [ ! -e "$link" ]
		}; then
			plan_change "Links" "Remove $(display_path "$link")"
			planned_pruned_links+=("$link")
		fi
	done
}

# Adds the skill links that setup will create, and the excluded skill links
# it will remove, to the setup preview.
#
# @param  {string}  target_dir
#     The installed skill directory.
plan_skill_links() {
	# The installed skill directory.
	local target_dir="$1"
	# The repository skill folder currently being checked.
	local skill
	# The skill's name, which is also its installed folder name.
	local slug
	# The installed path for the current skill.
	local skill_link

	for skill in "${skill_paths[@]}"; do
		slug=${skill##*/}
		skill_link="$target_dir/$slug"
		if ! skill_is_selected "$skill"; then
			if is_repo_owned_link "$skill" "$skill_link"; then
				plan_change "Links" "Remove excluded skill $(display_path "$skill_link")"
			fi
		else
			plan_link_path "$skill" "$skill_link"
		fi
	done
}
