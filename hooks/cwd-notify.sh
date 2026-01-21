#!/usr/bin/env bash
#
# CWD Change Notifier for Claude Code
# ====================================
#
# PROBLEM:
# When Claude Code runs a Bash command containing 'cd' (e.g., "mkdir -p foo && cd foo && npm pack"),
# the shell's working directory changes, but the LLM is NOT informed. The system prompt's
# <env>Working directory: X</env> is static (set at session start, never updated).
#
# This causes the LLM to:
# - Construct wrong absolute paths in subsequent tool calls
# - Try to 'cd' into directories it's already in
# - Use Search/Grep tools with non-existent paths
#
# ROOT CAUSE (from Claude Code source analysis):
# - PersistentShell correctly tracks cwd via temp file (pwd > cwdFile after each command)
# - getCwd() correctly returns current cwd
# - BUT: The recursive query() call reuses the SAME STATIC system prompt
# - AND: BashTool.renderResultForAssistant() doesn't include cwd info
# - Result: LLM never learns about directory changes
#
# HOW TO REPRODUCE THE BUG:
# 1. Start a Claude Code session in /some/project
# 2. Run: mkdir -p subdir && cd subdir && touch file.txt
# 3. Run: cd subdir && ls file.txt
#    → ERROR: "no such file or directory: subdir" (because you're already IN subdir)
# 4. Run: ls /some/project/file.txt
#    → ERROR: file is actually at /some/project/subdir/file.txt
#
# This mirrors GitHub issues #1669, #4100, #11067, #14122 (24+ reports of this bug)
#
# HOW TO VERIFY THE FIX:
# 1. Clear state: rm -f /tmp/claude-cwd-state
# 2. Run: mkdir -p testdir && cd testdir && touch marker.txt
# 3. EXPECTED IF FIXED: You receive a notification in the tool output:
#    "Note: Working directory changed from '/original/path' to '/original/path/testdir'"
# 4. Run: ls marker.txt
#    → SUCCESS: File found (because you know you're in testdir, not the parent)
# 5. Run: cd testdir
#    → ERROR: "no such file or directory" - AND you understand why (you're already there)
#
# EXPECTED IF BROKEN:
# - No notification after step 2
# - You might incorrectly try "cd testdir && ls marker.txt" thinking you're in the parent
# - You might use wrong absolute paths like "/original/path/marker.txt"
#
# SOLUTION:
# This PostToolUse hook detects when cwd changes and notifies the LLM via stderr + exit code 2.
# Per Claude Code's hook system:
# - Exit 0 + stdout: LLM cannot see it (only shown in transcript)
# - Exit 2 + stderr: Fed back to LLM for adjustment ← WE USE THIS
#
# HOW IT WORKS:
# 1. Reads 'cwd' field from JSON input (Claude Code's internal state, the source of truth)
# 2. Compares against previously stored cwd in /tmp/claude-cwd-state
# 3. If CHANGED: outputs notification to stderr + exits with code 2 → LLM sees it
# 4. If UNCHANGED: exits silently with code 0 → zero token overhead
#
# CONFIGURATION:
# Add to ~/.claude/settings.json:
# {
#   "hooks": {
#     "PostToolUse": [
#       {
#         "matcher": "Bash",
#         "hooks": [{ "type": "command", "command": "~/.claude/hooks/cwd-notify.sh" }]
#       }
#     ]
#   }
# }
#
# DEPENDENCIES:
# - python3 (for JSON parsing)
# - Bash
#
# AUTHOR: Created during debugging session analyzing Claude Code source
# DATE: January 2026
#

set -euo pipefail

STATE_FILE="/tmp/claude-cwd-state"

# Read JSON from stdin and extract cwd
INPUT=$(cat)
CURRENT_CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

# If we couldn't get cwd, exit silently
[[ -z "$CURRENT_CWD" ]] && exit 0

# Read previous cwd (empty string if file doesn't exist)
PREVIOUS_CWD=""
[[ -f "$STATE_FILE" ]] && PREVIOUS_CWD=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# Always update state file with current cwd
echo "$CURRENT_CWD" > "$STATE_FILE"

# If this is the first command or cwd hasn't changed, exit silently
[[ -z "$PREVIOUS_CWD" ]] && exit 0
[[ "$CURRENT_CWD" == "$PREVIOUS_CWD" ]] && exit 0

# CWD changed! Notify the LLM via stderr + exit code 2
echo "Note: Working directory changed from '$PREVIOUS_CWD' to '$CURRENT_CWD'" >&2
exit 2
