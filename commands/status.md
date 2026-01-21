---
description: Show current CWD tracking status and state file contents
---

# CWD Tracker Status

Show the current state of the CWD tracker including the state file and current directory.

## Instructions

1. Check if the state file exists and show its contents:
   ```bash
   echo "=== CWD Tracker Status ===" && \
   echo "State file: /tmp/claude-cwd-state" && \
   if [ -f /tmp/claude-cwd-state ]; then \
     echo "Last tracked CWD: $(cat /tmp/claude-cwd-state)" ; \
   else \
     echo "Last tracked CWD: (not initialized)" ; \
   fi && \
   echo "Current CWD: $(pwd)"
   ```

2. Report to the user in a clear format:
   - State file location
   - Last tracked working directory (or "not initialized" if file doesn't exist)
   - Current working directory
   - Whether they match (if both exist)
