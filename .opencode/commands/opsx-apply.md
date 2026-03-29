---
description: Implement tasks from an OpenSpec change using SDD workflow
agent: general
---

Implement tasks from an OpenSpec change using the SDD (Spec-Driven Development) workflow.

**Input**: Optionally specify a change name (e.g., `/opsx-apply add-auth`). If omitted, check conversation context or prompt for available changes.

**Steps:**

1. **Select the change**
   - If name provided, use it
   - Otherwise run: `openspec list --json`
   - Prompt user to select if ambiguous

2. **Check status:**
   ```bash
   openspec status --change "<name>" --json
   ```

3. **Get apply instructions:**
   ```bash
   openspec instructions apply --change "<name>" --json
   ```

4. **Read context files** listed in the instructions (proposal, specs, design, tasks)

5. **Implement tasks loop:**
   - Show current progress: "N/M tasks complete"
   - For each pending task, make the code changes
   - Mark task complete: `- [ ]` → `- [x]`
   - Continue until done or blocked

6. **Show completion status**

If blocked or error encountered, explain the issue and wait for guidance.

Run `/opsx-apply $ARGUMENTS` to use.
