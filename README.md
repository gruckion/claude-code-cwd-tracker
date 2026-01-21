# Claude Code CWD Tracker

A Claude Code plugin that fixes the working directory tracking bug. When Claude runs `cd` commands, it loses track of where it is—this hook tells it.

## The Problem

When Claude Code runs a Bash command containing `cd` (e.g., `mkdir -p foo && cd foo && npm pack`), the shell's working directory changes, but **Claude is never informed**. The system prompt's `<env>Working directory: X</env>` is static—set at session start and never updated.

This causes Claude to:
- Construct wrong absolute paths in subsequent tool calls
- Try to `cd` into directories it's already in
- Use Search/Grep tools with non-existent paths

**This bug has been reported 24+ times** in GitHub issues [#1669](https://github.com/anthropics/claude-code/issues/1669), [#4100](https://github.com/anthropics/claude-code/issues/4100), [#11067](https://github.com/anthropics/claude-code/issues/11067), [#14122](https://github.com/anthropics/claude-code/issues/14122), and others.

### Example of the Bug

```
You: "Download the package and extract it"

Claude runs: mkdir -p myproject && cd myproject && npm pack @some/package
✓ Works fine - Claude is now IN myproject/

Claude runs: cd myproject && tar -xzf package.tgz
✗ ERROR: "no such file or directory: myproject"
  (Claude tried to cd into a directory it's already in)

Claude runs: ls /original/path/package.tgz
✗ ERROR: file not found
  (File is actually at /original/path/myproject/package.tgz)
```

## The Solution

This plugin uses Claude Code's **hook system** to detect when the working directory changes and notify Claude via the tool output. Claude then knows exactly where it is and constructs correct paths.

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│  Claude runs: mkdir -p foo && cd foo && touch file.txt         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  PostToolUse hook fires after Bash command completes            │
│  Hook receives JSON with current cwd from Claude Code           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Hook compares current cwd against stored previous cwd          │
│  Previous: /home/user/project                                   │
│  Current:  /home/user/project/foo                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  CWD changed! Hook outputs to stderr + exits with code 2        │
│  "Note: Working directory changed from '...' to '...'"          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Claude receives notification in tool result                    │
│  Claude now knows it's in /home/user/project/foo                │
│  Subsequent commands use correct paths                          │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight**: Claude Code's hook system feeds `stderr` + exit code 2 back to the LLM. Exit code 0 with stdout is only shown in the transcript (invisible to Claude).

## Tech Stack

- **Language**: Bash
- **Dependencies**: Python 3 (for JSON parsing)
- **Claude Code Version**: 2.x+ (requires hook support)
- **Platform**: macOS, Linux (anywhere Bash runs)

## Prerequisites

- Claude Code CLI installed
- Python 3 (usually pre-installed on macOS/Linux)
- Bash shell

## Installation

### 1. Create the hooks directory

```bash
mkdir -p ~/.claude/hooks
```

### 2. Download the hook script

```bash
curl -o ~/.claude/hooks/cwd-notify.sh \
  https://raw.githubusercontent.com/gruckion/claude-code-cwd-tracker/main/hooks/cwd-notify.sh
```

Or clone the repository:

```bash
git clone https://github.com/gruckion/claude-code-cwd-tracker.git
cp claude-code-cwd-tracker/hooks/cwd-notify.sh ~/.claude/hooks/
```

### 3. Make it executable

```bash
chmod +x ~/.claude/hooks/cwd-notify.sh
```

### 4. Configure Claude Code

Add the hook to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/cwd-notify.sh"
          }
        ]
      }
    ]
  }
}
```

If you already have a `settings.json`, merge the hooks section with your existing configuration.

### 5. Restart Claude Code

The hook takes effect on new sessions.

## Verification

### Testing the Fix

Run this sequence to verify the hook is working:

```bash
# 1. Clear any existing state
rm -f /tmp/claude-cwd-state

# 2. Start a new Claude Code session and ask Claude to run:
mkdir -p testdir && cd testdir && touch marker.txt
```

**Expected if FIXED:**
- You see a notification: `Note: Working directory changed from '/your/path' to '/your/path/testdir'`
- Claude knows it's in `testdir`
- Running `ls marker.txt` works
- Running `cd testdir` fails with "no such file or directory" (Claude understands why)

**Expected if BROKEN:**
- No notification after the command
- Claude thinks it's still in the parent directory
- Claude might try `cd testdir && ls marker.txt` unnecessarily
- Claude uses wrong absolute paths

### Checking Hook Status

After any Bash command, you should see in the Claude Code output:
```
PostToolUse:Bash hook succeeded
```

If the working directory changed, you'll also see the notification in the tool result.

## Architecture

### File Structure

```
~/.claude/
├── hooks/
│   └── cwd-notify.sh      # The hook script
├── settings.json          # Claude Code configuration (you edit this)
└── ...

/tmp/
└── claude-cwd-state       # Stores last known cwd (auto-created)
```

### Hook Script Flow

```bash
┌──────────────────────────────────────────────────────────────┐
│ 1. Read JSON from stdin (Claude Code provides this)          │
│    Contains: { "cwd": "/current/path", ... }                 │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ 2. Extract 'cwd' field using Python                          │
│    python3 -c "import sys,json; print(json.load(...))"       │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ 3. Compare against /tmp/claude-cwd-state                     │
│    - If file doesn't exist: first command, save and exit 0   │
│    - If cwd unchanged: exit 0 (zero token overhead)          │
│    - If cwd changed: continue to notification                │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ 4. Output notification to stderr and exit 2                  │
│    echo "Note: Working directory changed..." >&2             │
│    exit 2                                                    │
│                                                              │
│    Why stderr + exit 2?                                      │
│    - Exit 0 + stdout: Only shown in transcript (LLM can't    │
│      see)                                                    │
│    - Exit 2 + stderr: Fed back to LLM for adjustment         │
└──────────────────────────────────────────────────────────────┘
```

### Why This Works

Claude Code's hook system has specific behavior:

| Exit Code | Output | LLM Sees It? | Use Case |
|-----------|--------|--------------|----------|
| 0 | stdout | No (transcript only) | Silent logging |
| 0 | stderr | No | Silent warnings |
| 1 | any | Yes (as error) | Block the action |
| 2 | stderr | Yes (as feedback) | **Inform the LLM** |

We use **exit code 2 + stderr** to feed information back to Claude without blocking the command.

### Root Cause Analysis

From analyzing Claude Code's source:

1. `PersistentShell` correctly tracks cwd via temp file (`pwd > cwdFile` after each command)
2. `getCwd()` correctly returns the current working directory
3. **BUT**: The recursive `query()` call reuses the **same static system prompt**
4. **AND**: `BashTool.renderResultForAssistant()` doesn't include cwd info
5. **Result**: The LLM never learns about directory changes

This hook works around the issue by injecting cwd change notifications into the tool output stream.

## Configuration Options

### Basic Configuration

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/cwd-notify.sh"
          }
        ]
      }
    ]
  }
}
```

### With Other Hooks

If you have other PostToolUse hooks, add this one to the array:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/cwd-notify.sh" },
          { "type": "command", "command": "~/.claude/hooks/your-other-hook.sh" }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/write-hook.sh" }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### Hook Not Running

**Symptom**: No "PostToolUse:Bash hook succeeded" message after Bash commands.

**Solutions**:
1. Verify `settings.json` syntax is valid JSON:
   ```bash
   cat ~/.claude/settings.json | python3 -m json.tool
   ```
2. Check the hook path is correct and file exists:
   ```bash
   ls -la ~/.claude/hooks/cwd-notify.sh
   ```
3. Ensure the hook is executable:
   ```bash
   chmod +x ~/.claude/hooks/cwd-notify.sh
   ```
4. Restart Claude Code (hooks are loaded at session start)

### Hook Runs But No Notification

**Symptom**: "PostToolUse:Bash hook succeeded" appears but no cwd change notification.

**Possible causes**:
1. **First command of session**: The hook silently initializes state on the first command
2. **CWD didn't actually change**: Commands without `cd` won't trigger notifications
3. **State file has current path**: Clear it with `rm -f /tmp/claude-cwd-state`

### Python Not Found

**Symptom**: Hook fails silently or errors about Python.

**Solution**:
```bash
# Check Python 3 is available
python3 --version

# If not installed (macOS)
brew install python3

# If not installed (Ubuntu/Debian)
sudo apt-get install python3
```

### JSON Parsing Error

**Symptom**: Hook runs but never detects changes.

**Debug**:
```bash
# Test the JSON parsing manually
echo '{"cwd": "/test/path"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))"
# Should output: /test/path
```

### Permission Denied

**Symptom**: Error about permission denied when running hook.

**Solution**:
```bash
chmod +x ~/.claude/hooks/cwd-notify.sh
```

### State File Issues

**Symptom**: Weird behavior, wrong notifications.

**Solution**:
```bash
# Clear the state file
rm -f /tmp/claude-cwd-state

# Check state file contents
cat /tmp/claude-cwd-state
```

## Performance

- **Zero overhead when cwd unchanged**: Hook exits immediately with code 0
- **Minimal overhead on change**: Single file read, one Python invocation, one file write
- **State file**: Tiny (just a path string in `/tmp/claude-cwd-state`)

## Limitations

- **Session-specific state**: The `/tmp/claude-cwd-state` file persists across sessions. If you start a new session in a different directory, the first `cd` might show a misleading "changed from" path. This is harmless—Claude gets the correct current path.

- **Requires Python 3**: Used for JSON parsing. Could be rewritten in pure Bash with `jq` as an alternative.

- **Single session**: If running multiple Claude Code sessions simultaneously, they share the same state file. This could cause incorrect notifications. For multi-session support, the state file path would need to include a session identifier.

## Related Issues

This plugin addresses these Claude Code GitHub issues:

- [#1669](https://github.com/anthropics/claude-code/issues/1669) - Working directory tracking
- [#4100](https://github.com/anthropics/claude-code/issues/4100) - cd command confusion
- [#11067](https://github.com/anthropics/claude-code/issues/11067) - Path resolution after cd
- [#14122](https://github.com/anthropics/claude-code/issues/14122) - LLM unaware of directory changes

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the hook manually
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Created during a debugging session analyzing Claude Code's source code
- Thanks to the Claude Code team for the extensible hook system
