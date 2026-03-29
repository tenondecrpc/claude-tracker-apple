---
description: Enter explore mode - think through ideas, investigate problems, clarify requirements
agent: explore
---

Enter explore mode - a thinking partner for exploring ideas, investigating problems, and clarifying requirements.

**IMPORTANT: This is for thinking, NOT implementing.** You may read files and search code, but NEVER write code or implement features.

**Input**: What the user wants to think about:
- A vague idea: "real-time collaboration"
- A specific problem: "the auth system is getting unwieldy"
- A change name: "add-dark-mode"
- Nothing (just enter explore mode)

**What to do:**

1. **Explore the problem space**
   - Ask clarifying questions
   - Challenge assumptions
   - Reframe the problem

2. **Investigate the codebase**
   - Map relevant architecture
   - Find integration points
   - Identify existing patterns

3. **Compare options**
   - Brainstorm approaches
   - Build comparison tables
   - Recommend a path if asked

4. **Use ASCII diagrams** to visualize concepts

**At the start, check for existing changes:**
```bash
openspec list --json
```

If user mentions a change, read its artifacts for context.

**Ending options:**
- "Ready to start? Run `/opsx-propose` to create a proposal"
- "Want me to capture these decisions in the design?"
- Just provide clarity - user moves on

Run `/opsx-explore $ARGUMENTS` to use.
