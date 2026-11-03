"""Find `git worktree add` commands in session transcripts.

Usage: transcript-worktrees.py <transcript.jsonl>...

Prints one "repo<TAB>worktree-path<TAB>branch" line per command found, with
simple shell variables from the same command line expanded. The repo is the
`git -C` target, else the preceding `cd` target, else the worktree path
itself (git resolves its repository from either). Parsing is best-effort:
plan.sh verifies every candidate against the actual repo before it becomes
a target.
"""
import json
import os
import re
import shlex
import sys

WT_OPTS_WITH_ARG = {"-b", "-B", "--reason", "--orphan"}


def expand(tok, env):
    tok = re.sub(r"\$\{(\w+)\}|\$(\w+)", lambda m: env.get(m.group(1) or m.group(2), m.group(0)), tok)
    if tok.startswith("~"):
        tok = os.path.expanduser(tok)
    return tok


def parse(command):
    env = {"HOME": os.environ.get("HOME", "")}
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        toks = list(lexer)
    except ValueError:
        return
    cwd = None
    i = 0
    while i < len(toks):
        t = toks[i]
        m = re.fullmatch(r"(\w+)=(.*)", t)
        if m:
            env[m.group(1)] = expand(m.group(2), env)
        elif t == "cd" and i + 1 < len(toks):
            cwd = expand(toks[i + 1], env)
        elif t == "git":
            j = i + 1
            repo = None
            while j < len(toks) and toks[j].startswith("-"):
                if toks[j] == "-C" and j + 1 < len(toks):
                    repo = expand(toks[j + 1], env)
                    if cwd and not os.path.isabs(repo):
                        repo = os.path.join(cwd, repo)
                    j += 2
                else:
                    j += 1
            if j + 1 < len(toks) and toks[j] == "worktree" and toks[j + 1] == "add":
                j += 2
                branch, path = "", None
                while j < len(toks) and toks[j] not in ("&&", "||", ";", "|"):
                    tok = toks[j]
                    if tok in WT_OPTS_WITH_ARG and j + 1 < len(toks):
                        if tok in ("-b", "-B"):
                            branch = expand(toks[j + 1], env)
                        j += 2
                        continue
                    if tok.startswith("-"):
                        j += 1
                        continue
                    if path is None:
                        path = expand(tok, env)
                    j += 1
                base = repo or cwd
                if path is not None and (base is not None or os.path.isabs(path)):
                    if not os.path.isabs(path):
                        path = os.path.normpath(os.path.join(base, path))
                    yield base or path, path, branch
                i = j
                continue
        i += 1


def main(files):
    seen = set()
    for f in files:
        try:
            fh = open(f, encoding="utf-8")
        except OSError:
            continue
        with fh:
            for line in fh:
                if "worktree add" not in line:
                    continue
                try:
                    msg = json.loads(line).get("message") or {}
                except json.JSONDecodeError:
                    continue
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
                        continue
                    if block.get("name") != "Bash":
                        continue
                    cmd = (block.get("input") or {}).get("command", "")
                    if "worktree add" not in cmd:
                        continue
                    for repo, path, branch in parse(cmd):
                        key = (repo, path)
                        if key in seen:
                            continue
                        seen.add(key)
                        print(f"{repo}\t{path}\t{branch}")


if __name__ == "__main__":
    main(sys.argv[1:])
