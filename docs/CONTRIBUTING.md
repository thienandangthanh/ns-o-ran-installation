# Contributing Guide

This guide covers development setup and code quality standards for contributors.

---

## Code Formatting and Linting

This repository uses **pre-commit** hooks with **ruff** to automatically format and lint Python code before commits.

### Initial Setup

1. **Install dependencies** (if not already done):
   ```bash
   cd ~/ns-O-RAN-installation
   source .venv/bin/activate
   uv sync
   ```

2. **Install pre-commit hooks**:
   ```bash
   uv run pre-commit install
   ```

The hooks will run automatically on every `git commit`. They will:
- Format code with `ruff format`
- Lint and auto-fix issues with `ruff check --fix`

### Manual Usage

You can run the hooks manually without committing:

```bash
# Run on all files
uv run pre-commit run --all-files

# Run on staged files only
uv run pre-commit run
```

### Ruff Configuration

Ruff configuration is in `pyproject.toml` under `[tool.ruff]`. Key settings:
- Line length: 100 characters
- Target Python version: 3.8+
- Enabled rule sets: pycodestyle, pyflakes, isort, flake8-bugbear, flake8-comprehensions, pyupgrade
- Excluded directories: `.claude/` and `.opencode/` (managed by `ck` command, not part of this repo's codebase)

### Bypassing Hooks (Not Recommended)

If you need to bypass hooks for a specific commit (e.g., WIP commits):
```bash
git commit --no-verify -m "your message"
```

**Note**: Only bypass hooks for temporary commits. All code should pass formatting checks before merging.

---

## Development Workflow

1. **Read the README** for project context and setup instructions.
2. **Follow development rules** in `./.claude/rules/development-rules.md` (YAGNI, KISS, DRY principles).
3. **Run tests** before pushing changes.
4. **Ensure code passes pre-commit hooks** before committing.

---

## Documentation

- Put important project docs in `docs/` and keep them updated.
- Follow the existing documentation style: concise, practical, and focused on actionable information.
