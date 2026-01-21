# CWD Tracker Plugin Implementation Plan

## Overview

Convert the existing CWD tracking hook into a proper Claude Code plugin using the [ivan-magda/claude-code-plugin-template](https://github.com/ivan-magda/claude-code-plugin-template) structure.

## Current State

```
claude-code-cwd-tracker/
├── README.md              # Comprehensive documentation
├── LICENSE                # MIT License
└── hooks/
    └── cwd-notify.sh      # The hook script (currently standalone)
```

## Target State

```
claude-code-cwd-tracker/
├── .claude-plugin/
│   ├── plugin.json        # Plugin metadata (required)
│   └── marketplace.json   # Marketplace registration
├── hooks/
│   └── hooks.json         # Hook configuration (PostToolUse:Bash)
├── scripts/
│   └── cwd-notify.sh      # Hook script (moved, uses ${CLAUDE_PLUGIN_ROOT})
├── commands/
│   ├── verify.md          # /cwd-tracker:verify - Test if hook is working
│   └── status.md          # /cwd-tracker:status - Show current CWD state
├── README.md              # Updated with plugin installation instructions
└── LICENSE                # MIT License
```

## Implementation Steps

### Phase 1: Plugin Structure

#### 1.1 Create `.claude-plugin/plugin.json`

```json
{
  "name": "cwd-tracker",
  "version": "1.0.0",
  "description": "Fixes the working directory tracking bug in Claude Code by notifying Claude when the CWD changes after cd commands",
  "author": {
    "name": "gruckion",
    "url": "https://github.com/gruckion"
  },
  "homepage": "https://github.com/gruckion/claude-code-cwd-tracker",
  "repository": "https://github.com/gruckion/claude-code-cwd-tracker",
  "license": "MIT",
  "keywords": ["cwd", "working-directory", "bash", "hooks", "bug-fix"]
}
```

#### 1.2 Create `.claude-plugin/marketplace.json`

```json
{
  "name": "cwd-tracker-marketplace",
  "owner": {
    "name": "gruckion",
    "email": "your-email@example.com"
  },
  "metadata": {
    "description": "CWD Tracker plugin for Claude Code",
    "version": "1.0.0"
  },
  "plugins": [
    {
      "name": "cwd-tracker",
      "description": "Fixes the working directory tracking bug by notifying Claude when CWD changes",
      "version": "1.0.0",
      "author": {
        "name": "gruckion"
      },
      "source": ".",
      "category": "bug-fixes",
      "tags": ["cwd", "working-directory", "bash", "hooks"],
      "keywords": ["cwd", "bash", "hooks", "bug-fix", "working-directory"]
    }
  ]
}
```

### Phase 2: Hook Configuration

#### 2.1 Create `hooks/hooks.json`

```json
{
  "description": "Notifies Claude when the working directory changes after Bash commands",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cwd-notify.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "rm -f /tmp/claude-cwd-state && echo '✓ CWD Tracker loaded: Working directory changes will be tracked'"
          }
        ]
      }
    ]
  }
}
```

**Key decisions:**
- Use `${CLAUDE_PLUGIN_ROOT}` for portable paths
- Add `SessionStart` hook to clear state and show load message
- 5-second timeout (script is very fast)

#### 2.2 Move and update script

Move `hooks/cwd-notify.sh` → `scripts/cwd-notify.sh`

The script itself doesn't need changes - it already uses absolute paths for the state file. The hook configuration handles the `${CLAUDE_PLUGIN_ROOT}` reference.

### Phase 3: Slash Commands

#### 3.1 Create `commands/verify.md`

A command to test if the CWD tracking is working:

```markdown
---
description: Verify that CWD tracking is working correctly
---

# Verify CWD Tracking

Test the CWD tracking hook by performing a directory change and checking for notifications.

## Instructions

1. Clear the state file: `rm -f /tmp/claude-cwd-state`
2. Create a test directory and cd into it: `mkdir -p /tmp/cwd-test-$$ && cd /tmp/cwd-test-$$`
3. Check if you received a notification about the CWD change
4. Report the results to the user:
   - If notification received: "✓ CWD tracking is working correctly"
   - If no notification: "✗ CWD tracking may not be working - check hook configuration"
5. Clean up: `cd / && rm -rf /tmp/cwd-test-$$`
```

#### 3.2 Create `commands/status.md`

A command to show current CWD tracking state:

```markdown
---
description: Show current CWD tracking status and state
---

# CWD Tracker Status

Show the current state of the CWD tracker.

## Instructions

1. Check if the state file exists: `ls -la /tmp/claude-cwd-state 2>/dev/null`
2. If it exists, show its contents: `cat /tmp/claude-cwd-state`
3. Show the current working directory: `pwd`
4. Report to the user:
   - State file path: /tmp/claude-cwd-state
   - Last tracked CWD: (contents of file or "Not initialized")
   - Current CWD: (output of pwd)
   - Match status: Whether they match
```

### Phase 4: Update README

Update the README.md to include:

1. **Plugin installation method** (primary):
   ```bash
   /plugin marketplace add gruckion/claude-code-cwd-tracker
   /plugin install cwd-tracker
   ```

2. **Manual installation method** (alternative)

3. **New commands section**:
   - `/cwd-tracker:verify` - Test the hook
   - `/cwd-tracker:status` - Show tracking state

4. Keep existing documentation about the bug and how it works

### Phase 5: Verification

Before committing:

1. Validate plugin structure matches template requirements
2. Ensure all scripts are executable
3. Test hook configuration format
4. Verify marketplace.json format

## File Changes Summary

| Action | File |
|--------|------|
| CREATE | `.claude-plugin/plugin.json` |
| CREATE | `.claude-plugin/marketplace.json` |
| CREATE | `hooks/hooks.json` |
| MOVE   | `hooks/cwd-notify.sh` → `scripts/cwd-notify.sh` |
| CREATE | `commands/verify.md` |
| CREATE | `commands/status.md` |
| UPDATE | `README.md` |
| DELETE | (old `hooks/cwd-notify.sh` location) |

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| State file conflicts between sessions | Document limitation; consider session-based state file in future |
| Python 3 dependency | Document prerequisite; consider jq alternative |
| Hook timeout | Set conservative 5s timeout |

## Success Criteria

1. Plugin can be installed via `/plugin marketplace add gruckion/claude-code-cwd-tracker`
2. Hook automatically activates after Bash commands
3. CWD changes are notified to Claude
4. `/cwd-tracker:verify` confirms working state
5. `/cwd-tracker:status` shows current tracking info
