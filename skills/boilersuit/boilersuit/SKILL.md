---
name: boilersuit
description: >
  Use this skill when using an existing Boilersuit generator to create repeatable project files, or creating or editing a project-owned generator under .boilersuit/generators/. For existing generators, inspect project support, list and describe generators, preview the complete planned file set, handle existing destinations, and generate only after preview. For authoring, use the installed CLI contract as the source of truth, plan before writing, run doctor before preview, and avoid copying schema details that can drift.
---

# Boilersuit

Use the guide for the job before changing project files or a generator.

## Pick your guide

| Job                                                                      | Guide                                                      |
| ------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Use an existing generator to create project files                        | [Using generators](references/using-generators.md)         |
| Create or edit a project-owned generator under `.boilersuit/generators/` | [Authoring generators](references/authoring-generators.md) |

Use the installed Boilersuit CLI as the source of truth for commands and output paths. Preview the complete result before generating files.
