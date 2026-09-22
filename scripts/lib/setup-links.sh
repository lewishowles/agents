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
	local path="$1"
	local backup_dir

	case "$path" in
		"$HOME"/.claude*/skills/*)   backup_dir="$(dirname "$(dirname "$path")")/backups/skills" ;;
		"$HOME"/.claude*/hooks/*)    backup_dir="$(dirname "$(dirname "$path")")/backups/hooks" ;;
		"$HOME"/.claude*/commands/*) backup_dir="$(dirname "$(dirname "$path")")/backups/commands" ;;
		"$HOME/.agents/skills/"*)    backup_dir="$HOME/.agents/backups/skills" ;;
		*)                           backup_dir="$(dirname "$path")" ;;
	esac

	local backup_base
	backup_base="$(basename "$path")"
	mkdir -p "$backup_dir"

	local old
	while IFS= read -r old; do
		trash "$old"
	done < <(find "$backup_dir" -maxdepth 1 -name "${backup_base}.bak.*" 2>/dev/null)

	local backup="$backup_dir/${backup_base}.bak.$(timestamp)"
	mv "$path" "$backup"
	printf '%s' "$backup"
}

# Prints a path with $HOME replaced by ~ for readable terminal output.
#
# @param  {string}  path
#     The absolute path to display.
display_path() {
	local path="$1"

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
	local path="$1"
	local label="$2"

	if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
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
	local dir="$1"
	local repo_prefix="$2"
	local label="$3"
	local remove_all="${4:-0}"

	[ -d "$dir" ] || return 0

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

# Creates a symlink from source to target, backing up any conflicting path.
#
# @param  {string}  source
#     The file or directory to link to.
# @param  {string}  target
#     The symlink path to create.
# @param  {string}  label
#     Human-readable name for output messages.
link_path() {
	local source="$1"
	local target="$2"
	local label="$3"

	if [ -L "$target" ]; then
		local current
		current=$(readlink "$target")

		if [ "$current" = "$source" ]; then
			cli_group_status muted "$label" "already linked"
			return
		fi

		local backup
		backup=$(backup_path "$target")
		ln -s "$source" "$target"
		cli_group_status warning "relinked $label" "backup at $(display_path "$backup")"
	elif [ -e "$target" ]; then
		local backup
		backup=$(backup_path "$target")
		ln -s "$source" "$target"
		cli_group_status warning "replaced $label" "backup at $(display_path "$backup")"
	else
		ln -s "$source" "$target"
		cli_group_status success "linked" "$label"
	fi
}

# Links each skill folder under skills/<group>/ into the given target
# directory, named after the folder. Excluded skill names are passed after the
# target directory. Returns 1 without creating any links when two groups hold a
# skill with the same name, because one link would replace the other. The array
# length checks keep macOS bash 3.2 from treating an empty array as unset under
# `set -u`.
#
# @param  {string}  target_dir
#     The directory to install skill symlinks into.
# @param  {string}  ...
#     Skill names that must not be linked.
link_skills() {
	local target_dir="$1"  # Directory to install skill symlinks into.
	shift
	local -a excluded_skills=("$@")  # Skill names that must not be linked.
	local skill  # Canonical skill directory currently being checked or linked.
	local slug  # Skill name taken from the canonical directory basename.
	local other  # Previously collected skill directory used for duplicate checks.
	local other_slug  # Skill name taken from the previously collected directory.
	local excluded  # Whether the current skill is excluded from this setup run.
	local excluded_skill  # Excluded skill name currently being checked.
	local skill_link  # Installed skill path currently being checked or removed.
	local current  # Link text currently being compared with the canonical path.
	local skill_paths=()  # Canonical skill directories that passed duplicate checks.

	for skill in "$REPO_DIR"/skills/*/*; do
		if [ ! -d "$skill" ]; then
			continue
		fi

		slug=$(basename "$skill")
		if [ "${#skill_paths[@]}" -gt 0 ]; then
			for other in "${skill_paths[@]}"; do
				other_slug=$(basename "$other")
				if [ "$other_slug" = "$slug" ]; then
					cli_group_status failed "duplicate skill name" "$slug: $(display_path "$other") and $(display_path "$skill")"
					return 1
				fi
			done
		fi

		skill_paths+=("$skill")
	done

	if [ "${#skill_paths[@]}" -gt 0 ]; then
		for skill in "${skill_paths[@]}"; do
			slug=$(basename "$skill")
			excluded=0
			if [ "${#excluded_skills[@]}" -gt 0 ]; then
				for excluded_skill in "${excluded_skills[@]}"; do
					if [ "$excluded_skill" = "$slug" ]; then
						excluded=1
						break
					fi
				done
			fi

			if [ "$excluded" = "1" ]; then
				skill_link="$target_dir/$slug"
				if [ -L "$skill_link" ]; then
					current=$(readlink "$skill_link")
					# The link text is compared as link_path wrote it, so a link to the same
					# checkout through another path form is left alone.
					if [ "$current" = "$skill" ]; then
						trash "$skill_link"
						cli_group_status warning "removed excluded skill" "skills/$slug"
					fi
				fi
				continue
			fi

			link_path "$skill" "$target_dir/$slug" "skills/$slug"
		done
	fi
}
