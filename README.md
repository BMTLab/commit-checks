# commit-checks

The checks of git hooks that only a commit can make:
the trailers of its message and the length of its lines,
the references to the paths that it renames or deletes,
and the files that it adds or leaves out.

[![CI][ci-badge]][ci]

## Features

- The commit-msg hook `trailers` finds each line that looks like a trailer
  but that git does not parse, such as a key of two words,
  a continuation without its indent,
  or a blank line inside the block of trailers.
- The commit-msg hook `line-length` finds each line of the message,
  the subject too, that is longer than 72 characters;
  only a line that holds a URL may run past.
  It counts characters, not bytes, so a Cyrillic letter counts once.
- The hook `references` finds each line of the index
  that still names a path that the commit renames or deletes,
  so a move leaves no stale reference behind;
  a changelog may keep the old names.
- The hook `temporary-files` stops a commit that adds a file
  that an editor, a merge or patch leaves behind,
  such as `notes.orig` or `.main.py.swp`.
- The hook `untracked-files` lists the untracked files
  that the commit leaves out, since the change may need one of them;
  it never stops a commit.
- It needs nothing beyond Python and git,
  so pre-commit installs nothing for it,
  and it checks nothing that `make check` can check on the working tree.

## Install

commit-checks needs git and Python 3.10 or newer as `python3`.
`make install` links the script into `~/.local/bin` as `commit-checks`,
for a run by hand; the hooks need no install.

A repository takes the hooks in its `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/BMTLab/commit-checks
    rev: v1.1.1
    hooks:
      - id: trailers
      - id: line-length
      - id: references
      - id: temporary-files
      - id: untracked-files
```

The config also needs `default_install_hook_types: [pre-commit, commit-msg]`,
so that `pre-commit install` sets up the hook of the message too.
`pre-commit autoupdate --freeze` moves `rev` to the newest tag
and pins the commit of that tag, with the tag in a comment.
The path of a local checkout works as `repo` too, pinned to a commit.

## Usage

pre-commit runs the commands while git makes a commit,
and each one also runs by hand:

```bash
commit-checks trailers .git/COMMIT_EDITMSG
commit-checks line-length .git/COMMIT_EDITMSG
commit-checks references --exclude 'docs/history/*.md'
commit-checks temporary
commit-checks untracked
```

- `trailers FILE`: every trailer of the message in FILE
  is one that git parses, and no blank line parts the trailers.
  A paragraph of prose may hold a line such as `Note: x`:
  only a paragraph that is mostly trailers counts as the block of trailers.
- `line-length FILE`: no line of the message in FILE,
  the subject included, is longer than 72 characters.
  A line that holds a URL, such as `See: https://...`, may run past.
- `references [--exclude GLOB]...`: no file of the index names a path
  that the commit renames or deletes, by its path,
  or by its file name when no other file of the index has that name.
  `CHANGELOG.md` may name the old paths, and each `--exclude`
  leaves out more files, by a glob from the top of the repository.
- `temporary`: the commit adds no file named like
  `*.orig`, `*.rej`, `*.bak`, `*.swp`, `*.swo`, `*~`, `.#*`, `#*#`, `*.tmp`,
  `.DS_Store` or `Thumbs.db`.
- `untracked`: the untracked files that git does not ignore, one per line;
  past the first 20, a line on stderr counts the rest.

Each finding is a line on stdout, and the lines on stderr say what to do.

## Exit codes

| Code | Name                 | Meaning                                                  |
| ---- | -------------------- | -------------------------------------------------------- |
| `0`  | success              | no finding                                               |
| `10` | `CC_ERR_USAGE`       | a wrong command line, or a message file it cannot read   |
| `20` | `CC_ERR_TRAILERS`    | a line that looks like a trailer is none that git parses |
| `30` | `CC_ERR_REFERENCES`  | a file names a path that the commit renames or deletes   |
| `40` | `CC_ERR_TEMPORARY`   | the commit adds a temporary file                         |
| `50` | `CC_ERR_GIT`         | git failed, such as outside a repository                 |
| `60` | `CC_ERR_LINE_LENGTH` | a line of the message is longer than 72 characters       |

## How it works

`trailers` and `line-length` drop the lines that git drops:
the diff of `git commit --verbose`, and the comments of the message.
A comment starts with `#`,
or with `core.commentChar` where the git config sets it,
and git drops the comments when the commit opens an editor,
or when `commit.cleanup` is `strip`.
`git commit -m` and `-F` keep them, and tell the hook so by `GIT_EDITOR=:`,
so the checks read those lines as text.
With `core.commentChar` set to `auto`, the hooks take `#`.
Run by hand, as `pre-commit run --hook-stage commit-msg`,
a message counts as one from an editor.
`trailers` then compares the last paragraph with the trailers
that `git interpret-trailers --parse` reads from it,
and `line-length` counts the characters of each line,
without the spaces at its end, which git drops too.
The other commands read the index, which holds what the commit adds:
`git diff --cached` gives the renames and the deletions,
and `git grep --cached` finds the old paths in the files that the commit keeps.
A directory that moves counts file by file,
so a reference to the directory itself stays unchecked.

## Development

```bash
make check    # the linters, the formats and the tests, as CI runs them
make hooks    # installs the git hooks of this repository, once per clone
```

The unit tests check the functions of the script under pytest and hypothesis.
The integration tests run the script in throwaway repositories
under `BATS_TEST_TMPDIR`, with a git config of their own.
`make check` runs them twice: with the `python3` of the machine,
and through `make test-floor` with Python 3.10, which uv brings,
since a hook runs under the `python3` of each machine that commits.
uv also brings ruff, mypy, ShellCheck, shfmt, rumdl, pre-commit,
actionlint and zizmor, at the versions of `uv.lock`; bats comes from the system.
CI runs `make check` on GitHub for each push and pull request.

## License

MIT, see [LICENSE](LICENSE).

[ci-badge]: https://github.com/BMTLab/commit-checks/actions/workflows/ci.yml/badge.svg
[ci]: https://github.com/BMTLab/commit-checks/actions/workflows/ci.yml
