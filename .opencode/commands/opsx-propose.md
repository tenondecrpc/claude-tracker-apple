---
description: Propose a new change - create all artifacts (proposal, design, tasks) in one step
agent: general
---

Propose a new change and generate all artifacts in one step using SDD workflow.

**Input**: The change name (kebab-case) OR a description of what to build.

**Steps:**

1. **If no input provided, ask what to build**
   - Prompt user to describe what they want to build or fix
   - Derive a kebab-case name (e.g., "add user auth" → `add-user-auth`)

2. **Create the change:**
   ```bash
   openspec new change "<name>"
   ```

3. **Get artifact build order:**
   ```bash
   openspec status --change "<name>" --json
   ```

4. **Create artifacts in sequence:**
   - Loop through artifacts in dependency order
   - For each: run `openspec instructions <artifact-id> --change "<name>" --json`
   - Read dependency artifacts for context
   - Create the artifact file

5. **Show final status**

**Artifacts created:**
- proposal.md (what & why)
- design.md (how)
- tasks.md (implementation steps)

When ready: run `/opsx-apply` to implement.

Run `/opsx-propose $ARGUMENTS` to use.
