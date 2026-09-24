# Claude Code Harness

A sandboxed harness for running Claude Code with fine-grained security policies.

## Prerequisites

- `openshell` gateway installed via `openshell/scripts/install.sh`
- `ANTHROPIC_API_KEY` environment variable set when running Claude Code

## Profiles

The Claude Code harness supports four profiles, each with different filesystem and network restrictions:

| Profile | Use Case | Filesystem | Network | Landlock |
|---------|----------|-----------|---------|----------|
| `review` | Read-only code review | Workspace read-only, sandbox write | Model API only | hard_requirement |
| `dev` | Interactive development | Full read-write access | Model + GitHub + npm/PyPI | best_effort |
| `automation` | CI/CD automation | Full read-write access | Model + read-only GitHub + npm | hard_requirement |
| `interactive` | Long-running sessions with persistent data | Full read-write + persistent volume | Model + GitHub + npm + docs sites | best_effort |

## Usage

### Create a harness

```bash
# Create a development harness (default: claude-dev)
openshell/harnesses/claude/create.sh --profile dev

# Create a harness with a custom name
openshell/harnesses/claude/create.sh --profile review --name claude-review

# Create a review harness
openshell/harnesses/claude/create.sh --profile review

# Create an automation harness
openshell/harnesses/claude/create.sh --profile automation

# Create an interactive harness
openshell/harnesses/claude/create.sh --profile interactive
```

### Connect to a harness

```bash
# Connect to the default dev harness (claude-dev)
openshell/harnesses/claude/connect.sh

# Connect to a specific harness
openshell/harnesses/claude/connect.sh --name claude-review
```

## Harness Version

The Claude Code harness is pinned to `@anthropic-ai/claude-code@2.1.281` for reproducibility.

To check for updates:
```bash
npm view @anthropic-ai/claude-code version
```
