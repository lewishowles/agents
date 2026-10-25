---
name: python
description: >
  Use this skill when writing or editing Python files (.py, pyproject.toml), including
  scripts, modules, command-line tools, and tests. Covers Python comments, declaration order,
  types, structured results, and project formatter settings.
---

# Python

Use `code-style` for the structure standard, split signals, and rules shared across languages. This skill supplies the Python conventions for applying them. Use `bash` for shell scripts; this skill does not apply to shell-only changes.

## Comments and layout

- Put a short purpose comment above every variable, constant, and field, including local values. Group declarations at the top of each function or block where their values are available, then separate distinct steps with blank lines.
- Give every module, function, method, and class a docstring, even when its name and type hints look clear. Start with one line saying what it is for. When a function takes parameters, list each under `Args:`, then describe the result under `Returns:` and any exception callers should handle under `Raises:`.
- In a standalone script, put the module docstring straight after the shebang, and include execution order or external constraints when they matter.
- Avoid banner dividers. Use headings only when they make a long module easier to scan.

```python
"""Build the skill index from each skill's SKILL.md."""

# Listed first in the index so it appears near the slash-command docs.
PM_GROUP = "project-management"


def load_manifest(skill_dir: Path) -> SkillManifest:
	"""Read a skill's SKILL.md and return the fields the index needs.

	Args:
		skill_dir: The skill directory containing SKILL.md.

	Returns:
		The skill's name, description, and group.

	Raises:
		ManifestError: SKILL.md is missing or its frontmatter is invalid.
	"""
	…
```

## File order

Put imports and module values first, then the main functions, then the helpers those functions call, as in the JavaScript module order in `code-style`. A function only has to exist by the time it is called, so helpers can sit below their callers. Dataclasses, enums, and other types go with the module values, above the functions that use them, because Python evaluates type hints when a function is defined and a type named before it exists raises `NameError`. End executable scripts with `if __name__ == "__main__":` calling `main()`.

## Python structure tools

- Add type hints to parameters, return values, fields, and values whose type is not clear from the assignment. Return a named type for a successful result rather than a bare tuple or dictionary.
- Use dataclasses for records with named fields and enums for a fixed set of statuses. Use exceptions for failures; do not mix error strings with successful result values.
- Use `match` when handling several distinct result shapes or statuses is clearer than nested conditionals. Keep a direct `if` when there are only one or two simple cases.
- Put a small typed wrapper around each command-line tool or database boundary. Parse its output once there, then let the rest of the code work with named values rather than raw output or loose dictionaries.

## Project settings

Follow the Python version and Ruff configuration of the package you're editing for indentation, line length, and formatting. Settings can differ between packages in the same repository: in agent-tools, `progress` sets tabs in `[tool.ruff.format]` while `agent-run` keeps Ruff's default four spaces. Never reformat a file to another package's settings.
