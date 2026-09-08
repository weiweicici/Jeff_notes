# Cross-Machine Synchronization Guide (Windows & Mac)

This guide establishes the standard Git workflow to keep Windows and macOS development environments in sync using GitHub as the single source of truth.

---

## Standard Workflow

### 1. Before Starting Work (Every Session)
Always verify your local status and pull latest changes before modifying code:
```bash
git status
git pull
```

### 2. After Finishing Work (Before Leaving a Machine)
Check your changes, stage only intended files, commit, and push:
```bash
git status
git add <specific-files>
git commit -m "Descriptive summary of changes"
git push
```

### 3. When Switching Between Machines
- **Machine A (leaving)**: Complete work, commit, and `git push`. Confirm `git status` shows working tree clean and up to date with origin.
- **Machine B (arriving)**: Before opening or editing files in your editor, open a terminal and run `git pull`.

---

## Safe Recovery Procedures

### A. Local Uncommitted Changes on Destination Machine
If `git pull` is blocked because of local modifications or ephemeral build artifacts on the destination machine:
- Inspect what changed:
  ```bash
  git status
  git diff
  ```
- If changes are temporary or ephemeral (e.g. build timestamps or platform registrants):
  ```bash
  git restore <file>
  # or stash them safely:
  git stash
  git pull
  ```

### B. Pull Conflict (Merge Conflict)
If both machines modified the same tracked files and a pull produces merge conflicts:
- Check conflicted files:
  ```bash
  git status
  ```
- Open each conflicted file, locate conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`), resolve to the desired logic, and save.
- Run tests and static analysis to verify correctness:
  ```bash
  flutter analyze
  flutter test
  ```
- Stage resolved files and complete merge:
  ```bash
  git add <resolved-files>
  git commit -m "Resolve cross-machine merge conflict"
  git push
  ```

### C. Branch Mismatch
Ensure both machines are on the intended feature or development branch:
- Check current branch and tracking:
  ```bash
  git branch -vv
  ```
- Switch to the active development branch if needed:
  ```bash
  git checkout <target-branch>
  git pull
  ```

### D. Verifying Current State Against GitHub
Check the latest 3 commits to ensure your machine matches remote HEAD:
```bash
git log -n 3 --oneline
git fetch origin
git status
```
When working tree says:
`Your branch is up to date with 'origin/<branch>'. Nothing to commit, working tree clean`
your machine is in sync.

---

## Critical Rules
1. **Never commit credentials, keys, or secrets**: API keys (Gemini, Groq, OpenAI, etc.) must remain in secure storage or local `.env` files and never be staged.
2. **Never commit heavy acceptance media**: Audio files (`.mp4`, `.wav`), video recordings, listening packs, and extracted clip slices are ignored by `.gitignore` and must remain local.
3. **Do not force push (`git push -f`)**: Always synchronize with linear commits or clean merges to avoid rewriting history shared between machines.
