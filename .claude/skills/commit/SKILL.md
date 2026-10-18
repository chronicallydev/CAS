---
name: commit
description: Stage and commit the current changes in this repo with a clear message. Use when the user types /commit.
disable-model-invocation: true
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*)
---

Commit the current working-tree changes.

1. Run `git status --short` and `git diff` (plus `git diff --cached`) to see what changed. If there is nothing to commit, say so and stop.
2. Run `git log --oneline -5` to match the existing message style.
3. Stage the changes with `git add -A` (`.gitignore` already excludes `.godot/`). Do not stage anything that looks like secrets or large build output; mention it instead.
4. Write a commit message: a short imperative summary line (under ~60 chars), then a blank line and a few bullet points if the change is non-trivial.
5. Do NOT add any `Co-Authored-By: Claude` trailer or "Generated with Claude Code" line — plain message only.
6. Commit, then show `git log --oneline -1`.
7. Do not push unless the user's arguments ask for it (e.g. `/commit push`), in which case run `git push`.

User arguments (optional extra instructions or message hint): $ARGUMENTS
