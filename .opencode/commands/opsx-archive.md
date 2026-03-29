---
description: Archive a completed change in the experimental workflow
agent: general
---

Archive a completed change in the OpenSpec workflow.

**Input**: Optionally specify a change name (e.g., `/opsx-archive add-auth`). If omitted, prompt for available changes.

**Steps:**

1. **If no change name, prompt for selection**
   - Run: `openspec list --json`
   - Show active changes for user to select

2. **Check artifact completion:**
   ```bash
   openspec status --change "<name>" --json
   ```
   - If incomplete artifacts exist, warn user and confirm before proceeding

3. **Check task completion:**
   - Read tasks file, count `- [ ]` vs `- [x]`
   - If incomplete tasks, warn user and confirm

4. **Check delta specs sync:**
   - If delta specs exist at `openspec/changes/<name>/specs/`
   - Compare with main specs, show summary
   - Prompt for sync or skip

5. **Perform archive:**
   ```bash
   mkdir -p openspec/changes/archive
   mv openspec/changes/<name> openspec/changes/archive/YYYY-MM-DD-<name>
   ```

6. **Show summary** with archive location and any warnings

Run `/opsx-archive $ARGUMENTS` to use.
