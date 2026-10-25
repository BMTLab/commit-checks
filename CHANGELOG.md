# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog][keepachangelog],
and this project adheres to [Semantic Versioning][semver].

## [Unreleased]

### Fixed

- The hook `trailers` failed on a message with trailers
  that was written in an editor:
  it took the files that git lists under the message, after `#` and a tab,
  for lines of the message.
  Now every line that starts with `#` counts as a comment,
  as it does for git in an editor.

## [1.0.1] - 2026-10-25

### Fixed

- The hooks ran only under Python 3.14.
  An older `python3` stopped at once: 3.12 and 3.13 with a `NameError`
  on the annotations, and 3.11 and older with a `SyntaxError`.
  They now run under Python 3.10 or newer,
  and `make check` runs the tests under 3.10 too.

## [1.0.0] - 2026-10-24

### Added

- The hooks `trailers`, `references`, `temporary-files` and `untracked-files`
  for pre-commit, and the command `commit-checks`, which runs them by hand too.

[keepachangelog]: https://keepachangelog.com/en/1.1.0/
[semver]: https://semver.org/spec/v2.0.0.html
[Unreleased]: https://github.com/BMTLab/commit-checks/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/BMTLab/commit-checks/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/BMTLab/commit-checks/releases/tag/v1.0.0
