---
description: Verify that CWD tracking is working correctly
---

# Verify CWD Tracking

Test the CWD tracking hook by performing a directory change and checking for notifications.

## Instructions

1. First, clear the state file by running: `rm -f /tmp/claude-cwd-state`
2. Create a test directory and cd into it: `mkdir -p /tmp/cwd-verify-test && cd /tmp/cwd-verify-test`
3. Check if you received a notification about the CWD change in the tool output
4. Report the results to the user:
   - If you see "Note: Working directory changed from..." → "✓ CWD tracking is working correctly"
   - If no notification appeared → "✗ CWD tracking may not be working - check hook configuration"
5. Clean up by running: `rm -rf /tmp/cwd-verify-test`
6. Summarize: state whether the CWD tracker is functioning properly
