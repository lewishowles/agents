# Catppuccin skin

A small Claude Code mod that colours tool headers, Bash result borders, and turn footers with Catppuccin Mocha or Latte. It leaves prompts and ordinary assistant prose to Claude Code. Tool blocks and the turn footer get a little extra space.

In verbose mode and the ctrl+o transcript, tool rows inside expanded groups show the skin's header without their inline output.

Try it from this repository with `claude --plugin-dir src/plugins/skin`. The plugin chooses Latte for a light Claude theme or a light `COLORFGBG` terminal background; otherwise it uses Mocha.

Inspired by [hellosverre/claude-skins](https://github.com/hellosverre/claude-skins), which is MIT licensed. This mod is a separate implementation.
