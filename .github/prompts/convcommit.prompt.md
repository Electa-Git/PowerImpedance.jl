---
description: 'Prompt and workflow for generating short, objective, and factual conventional commit messages. Enforces a strict, minimalist style focused solely on describing the change.'
tools: ['runCommands', 'runInTerminal', 'getTerminalOutput']
---

### Instructions
<description>
This prompt generates conventional commit messages. The messages must be short, objective, and factual. They state *what* changed, not *why* or *how*. There are no justifications, no explanations of benefits, and no redundant information.
</description>

### Atomic Commit Workflow
The golden rule is one logical change per commit. Do not bundle unrelated changes. Follow this iterative process:

1.  Run `git status` to see all modified files.
2.  Run `git diff` to identify a single, self-contained logical change.
3.  Stage only the file(s) for that single change. Use `git add path/to/file`.
4.  Construct a commit message for the staged change using the XML structure below.
5.  Use the `runInTerminal` tool to execute the commit.
6.  Repeat until the working directory is clean.

### Commit Message Structure

```xml
<commit-message>
    <type>feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert</type>
    <scope>()</scope>
    <description>A short, imperative summary of what changed</description>
    <body>(optional: A more detailed, factual description of what changed. No justifications.)</body>
    <footer>(optional: e.g. BREAKING CHANGE: details, or issue references like "Fixes #123")</footer>
</commit-message>
```

### Strict Commit Message Style Rules

```xml
<writing-style-rules>
    <rule id="1" name="State Only What Changed">
        <description>The message must only describe the change. Do not include justifications, rationale, or explanations of benefits. The value of the change must be self-evident from the description.</description>
        <good-example>refactor(engine): Rename Core module to Engine.</good-example>
        <bad-example>refactor(engine): Rename Core module to Engine to better reflect its role.</bad-example>
    </rule>
    <rule id="2" name="Be Factual and Objective">
        <description>Avoid subjective terms like "improve," "enhance," "simplify," or "clarify." State the action taken. The code's quality is not the subject of the commit message.</description>
        <good-example>refactor(fem): Move FEM options into FEMFormulation constructor.</good-example>
        <bad-example>refactor(fem): Simplify FEM API by merging options into the constructor.</bad-example>
    </rule>
    <rule id="3" name="Omit Redundant Information">
        <description>Do not list file renames or other changes that are self-evident from the commit's file list. The git history is the source of truth for which files were changed.</description>
    </rule>
    <rule id="4" name="Use the Imperative Mood">
        <description>Write the description in the imperative mood (e.g., "add," "fix," "change," not "added," "fixed," or "changed").</description>
    </rule>
</writing-style-rules>
```

```xml
<anti-patterns>
    <anti-pattern name="Justification and Verbosity">
        <description>The following is an example of a commit message body that is TOO LONG and contains justifications and subjective information. DO NOT generate messages like this.</description>
        <example-body>
        The Core module is renamed to Engine to better reflect its role as the central computation component. This refactoring introduces a centralized `interfaces.jl` file for physical constants and abstract API definitions, improving modularity and simplifying dependencies. Extensive input validation is added to the `LineParametersProblem` constructor to ensure model integrity.
        </example-body>
    </anti-pattern>
</anti-patterns>
```

### Examples

```xml
<examples>
    <example>feat(parser): add ability to parse arrays</example>
    <example>fix(ui): correct button alignment</example>
    <example>docs: update README with usage instructions</example>
    <example>refactor(api): extract user validation to `isValidUser` function</example>
    <example>chore: update dependencies</example>
    <example>feat!: send email on registration (BREAKING CHANGE: email service required)</example>
</examples>
```

### Commit Loop

```xml
<commit-loop>
    <cmd>git add path/to/file.ext</cmd>
    <cmd>git commit -m "type(scope): description"</cmd>
    <note>Replace with your constructed message. Do not use backticks for file paths.</note>
</commit-loop>
```

### Important
Commit all modified and untracked files according to the atomic commit workflow in convcommit.prompt.md. Do not stop for confirmation. Continue until the working directory is clean. This prompt is structured using XML for clarity, but do not include XML tags in your commit messages. Never assume that the user has staged files correctly or that the work tree is clean. Always check `git status` and `git diff` when you receive this prompt.