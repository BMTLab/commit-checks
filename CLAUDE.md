# Working in this repository

commit-checks gives git hooks the checks that only a commit can make:
the trailers of the message and the length of its lines,
the references to the paths it moves, and the files it adds or leaves out.
pre-commit runs it from `.pre-commit-hooks.yaml`,
in the repositories that take its hooks.

## Map

- `commit-checks.py`: the one script, in regions: Constants, Errors, git,
  Message, Trailers, Line length, References, Index and Commands.
- `.pre-commit-hooks.yaml`: the hooks that a repository takes by their ids.
- `tests/commit-checks.bats`: the tests, in throwaway repositories;
  `tests/support/helpers.bash` makes them.
- `pyproject.toml`: the settings of ruff and mypy; there is no package.
- `Makefile`: every task; `make help` lists them.
- `.pre-commit-config.yaml`, `committed.toml`: the git hooks of `make hooks`,
  which check only what a commit adds and its message.

## Before and after a change

- Run `make check`: it must be green before you start and after you finish.
- A check belongs here only when nothing but a commit can show it:
  the message, or the index against HEAD.
  What holds for the working tree, such as a linter, belongs in `make check`
  of the repository that wants it.
- A new hook gets its id in `.pre-commit-hooks.yaml`,
  its command in the script, a test, and a line in the README.
- A repository pins this one by a commit, so a change reaches it
  only when it moves its `rev`.

## Language and punctuation

- Text, comments and messages are in simple English:
  one idea in each sentence, common words, and the active voice.
- A comment says why, or what the code does not show at a glance.
- No em dash, no en dash and no curly quotes:
  rumdl finds them in the Markdown files, and a hook finds the em dash
  in the message of a commit.
- The README keeps its order: Features, Install, Usage, Exit codes,
  How it works, Development and License.

## Python

- The code keeps to Python 3.10, since a hook runs
  under the `python3` of each machine that commits:
  ruff and mypy check it as 3.10, and `make test-floor` runs the tests there.
- The standard library only, so a commit never waits for an install.
- git runs through `run_git` alone, with an argv list and a timeout,
  and its output is read as bytes.
- A failure that the script expects ends with its code and a message,
  and anything else shows its traceback.

## Exit codes

The card, `--help` and the README list every code, and a test checks:
10 for usage, 50 for git, and one code for each check in the other tens.
A new code takes the next free ten.

## Tests

- One rule per test, named as a sentence,
  in the sections Arrange, Act and Assert.
- Each test makes its repository under `BATS_TEST_TMPDIR`,
  with a git config of its own, so the config of the machine changes nothing.

## Versions and git

- `VERSION` in the script and the CHANGELOG move together,
  under `## [Unreleased]` until a release.
- A release dates the section of its version, as `## [1.0.0] - 2026-10-24`,
  and the signed tag `vX.Y.Z` sits on that commit:
  other repositories pin the hooks by that tag,
  from `github.com/BMTLab/commit-checks`.
- One branch, `main`, and every commit is signed.
- A commit message has a subject in the imperative mood,
  of at most 72 characters, and a body of git trailers,
  such as `Why:`, `Rejected:` and `Verified:`.
  The hooks of `make hooks` check the subject, the trailers
  and the length of each line.
- Nothing is pushed without the word of the user.
