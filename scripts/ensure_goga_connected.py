#!/usr/bin/env python3
"""
Verifies (and if needed, (re-)establishes) the global goga-claude skill connection that
Condition B' relies on. `goga connect` is a machine-wide, singleton operation (writes
~/.goga/skills, ~/.goga/commands, symlinks into ~/.claude/skills -- see PROTOCOL.md Amendment
5) -- it is NOT re-run per B' execution, only once here before the B' batch starts.
"""
import os
import subprocess
import sys

GOGA_BIN = os.path.expanduser("~/.local/bin/goga")


def main():
    if not os.path.exists(GOGA_BIN):
        print(f"ERROR: goga binary not found at {GOGA_BIN}", file=sys.stderr)
        sys.exit(1)

    version = subprocess.run([GOGA_BIN, "--version"], capture_output=True, text=True)
    print(f"goga version: {version.stdout.strip()}")

    skills_dir = os.path.expanduser("~/.claude/skills")
    goga_skills = [d for d in os.listdir(skills_dir) if d.startswith("goga-")]
    print(f"goga-* skills currently symlinked in ~/.claude/skills: {len(goga_skills)}")

    if len(goga_skills) == 0:
        print("No goga-* skills found -- running `goga connect claude`...")
        result = subprocess.run([GOGA_BIN, "connect", "claude"], capture_output=True, text=True)
        print(result.stdout, result.stderr)
        if result.returncode != 0:
            print("ERROR: goga connect claude failed", file=sys.stderr)
            sys.exit(1)
    else:
        print("Already connected -- not re-running goga connect (force_overwrite=False is the "
              "default and would be a no-op anyway, but this avoids the churn/logging noise of "
              "an unnecessary re-sync).")

    print("OK: goga is installed and connected for Condition B' runs.")


if __name__ == "__main__":
    main()
