#!/usr/bin/env python3
"""Print the `run:` script of a composite-action step with ${{ }} expressions substituted.

Usage: extract-step.py <action.yml> <step-id> [EXPR=VALUE ...]
EXPR is the text inside ${{ }}, e.g. github.repository=o/r. Unsubstituted
expressions are an error, so a test never runs a script with literal ${{ }}.
"""
import re
import sys

import yaml

path, step_id, *pairs = sys.argv[1:]
steps = yaml.safe_load(open(path, encoding="utf-8"))["runs"]["steps"]
step = next((s for s in steps if s.get("id") == step_id), None)
if step is None:
    sys.exit(f"no step with id {step_id} in {path}")
run = step["run"]
for pair in pairs:
    expr, value = pair.split("=", 1)
    run = run.replace("${{ %s }}" % expr, value)
left = re.findall(r"\$\{\{[^}]*\}\}", run)
if left:
    sys.exit(f"unsubstituted expressions in step {step_id}: {sorted(set(left))}")
sys.stdout.write(run)
