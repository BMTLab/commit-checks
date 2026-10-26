#!/usr/bin/env -S python3 -I
"""Check what nothing but a commit can show, for the git hooks of pre-commit.

Usage: commit-checks COMMAND [ARGUMENT...]
Effects: none; it reads the index and the message of a commit,
  and changes neither.
Dependencies: git, and Python 3.10 or newer as python3.
Exit codes:
  0 success,
  10 CC_ERR_USAGE,
  20 CC_ERR_TRAILERS,
  30 CC_ERR_REFERENCES,
  40 CC_ERR_TEMPORARY,
  50 CC_ERR_GIT,
  60 CC_ERR_LINE_LENGTH.
See: commit-checks --help, README.md, tests/.

How it works:
  pre-commit runs each command from .pre-commit-hooks.yaml while git makes a commit:
  trailers and line-length on the message, and the other commands on the index,
  which holds what the commit adds to the history.
  Each finding is a line on stdout, and the last lines on stderr say what to do.
  A check that also holds for the working tree, such as a linter or a test,
  belongs in make check instead, so it has no command here.

Version: 1.1.2
"""

# Python 3.13 and older evaluate annotations when a def runs,
# and the names of TYPE_CHECKING below exist only for mypy.
from __future__ import annotations

import fnmatch
import os
import re
import shutil
import subprocess  # ruff: ignore[suspicious-subprocess-import], git is the point
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import TYPE_CHECKING, Final, TextIO

if TYPE_CHECKING:
    from collections.abc import Callable, Sequence

# region Constants

PROGRAM: Final = "commit-checks"
VERSION: Final = "1.1.2"

CC_ERR_USAGE: Final = 10
CC_ERR_TRAILERS: Final = 20
CC_ERR_REFERENCES: Final = 30
CC_ERR_TEMPORARY: Final = 40
CC_ERR_GIT: Final = 50
CC_ERR_LINE_LENGTH: Final = 60

# git grep ends with 1 when nothing matches, which is no failure.
GIT_GREP_NO_MATCH: Final = 1
# git config ends with 1 when it finds no key, which is no failure.
GIT_CONFIG_UNSET: Final = 1
# A git command that takes longer than this hangs, such as on a lock.
GIT_TIMEOUT_SECONDS: Final = 60

# A trailer opens with a token, a colon and a space, as git reads it by default.
TRAILER_LINE_PATTERN: Final = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*: \S")
# git commit --verbose puts the diff below this line, and the message ends there.
SCISSORS: Final = "------------------------ >8 ------------------------"
COMMENT_CHARACTER: Final = "#"
# The settings that decide which lines of a message git drops as comments.
COMMENT_SETTINGS: Final = r"^(core\.commentstring|core\.commentchar|commit\.cleanup)$"
# git sets GIT_EDITOR to this for the hooks of a commit that opens no editor, as -m and -F do.
NO_EDITOR: Final = ":"
# The longest line of a message, in characters:
# git log indents each line by four spaces, and 72 of them still fit in 80 columns.
LINE_LENGTH_LIMIT: Final = 72
# A URL cannot break, so a line that holds one may run past the limit.
URL_PATTERN: Final = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://\S")

# The files that editors, merge tools and patch leave behind.
TEMPORARY_PATTERNS: Final = (
    "*.orig",
    "*.rej",
    "*.bak",
    "*.swp",
    "*.swo",
    "*~",
    ".#*",
    "#*#",
    "*.tmp",
    ".DS_Store",
    "Thumbs.db",
)
# A changelog names an old path on purpose: it is history.
REFERENCE_EXCLUDES: Final = ("**/CHANGELOG.md",)
# A name stands alone when no letter, digit, underscore, dot or hyphen touches it:
# a slash may come before it, as in rules/old.md, and a full stop after it.
NAME_BEFORE: Final = "(^|[^[:alnum:]_.-])"
NAME_AFTER: Final = "([^[:alnum:]_-]|$)"
# The characters that the extended regular expressions of git grep take as special.
ERE_SPECIAL_PATTERN: Final = re.compile(r"([.\[\]()*+?{}|^$\\])")

# What to do next when git fails, by the kind of the failure.
NEXT_STEP_NO_GIT: Final = "install git, or put it on PATH"
NEXT_STEP_GIT_HANGS: Final = "end the other git of this repository, then try again"
NEXT_STEP_GIT_FAILS: Final = "run commit-checks inside a git repository, or fix what git says"

# The untracked files that untracked lists before it counts the rest.
UNTRACKED_SHOWN: Final = 20

HELP: Final = f"""\
Usage: commit-checks COMMAND [ARGUMENT...]

Check what nothing but a commit can show, for the git hooks of pre-commit.

Commands:
  trailers FILE        Every trailer of the commit message in FILE is one that git parses,
                       and no blank line parts the trailers.
  line-length FILE     No line of the message in FILE runs past {LINE_LENGTH_LIMIT} characters,
                       apart from a line that holds a URL.
  references [--exclude GLOB]...
                       No file of the index names a path that the commit renames or deletes.
                       CHANGELOG.md may keep the old names; GLOB leaves out more files.
  temporary            The commit adds no temporary file, such as a .orig, .rej, .bak or .swp.
  untracked            List the untracked files, which the commit leaves out; never fails.
  --help               Print this help.
  --version            Print the version.

Exit codes:
  0   success
  10  CC_ERR_USAGE: a wrong command line, or a message file it cannot read
  20  CC_ERR_TRAILERS: a line that looks like a trailer is none that git parses
  30  CC_ERR_REFERENCES: a file names a path that the commit renames or deletes
  40  CC_ERR_TEMPORARY: the commit adds a temporary file
  50  CC_ERR_GIT: git failed, such as outside a repository
  60  CC_ERR_LINE_LENGTH: a line of the message is longer than {LINE_LENGTH_LIMIT} characters
"""

# endregion Constants

# region Errors


class UsageError(Exception):
    """A command line that commit-checks cannot run."""


class GitError(Exception):
    """A git command that failed, with the words git printed and what to do next."""

    def __init__(self, message: str, next_step: str) -> None:
        """Keep the words of the failure and the next step.

        Parameters
        ----------
        message
            What went wrong, such as the words that git printed.
        next_step
            What the user does next, such as ``install git, or put it on PATH``.
        """
        super().__init__(message)
        self.next_step = next_step


# endregion Errors

# region git


def run_git(arguments: Sequence[str], stdin: bytes = b"", accepted: int = 0) -> bytes:
    """Run git and return what it prints on stdout.

    Parameters
    ----------
    arguments
        The arguments after ``git``.
    stdin
        What git reads on its stdin.
    accepted
        One more exit status that is no failure, besides 0.

    Returns
    -------
    bytes
        The stdout of git, as bytes, since a path may be in no encoding at all.

    Raises
    ------
    GitError
        When git is missing, fails or hangs.
    """
    executable = shutil.which("git")

    if executable is None:
        message = "git is not on PATH"

        raise GitError(message, NEXT_STEP_NO_GIT)

    try:
        completed = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true], git by its full path, with an argv list
            [executable, *arguments],
            input=stdin,
            capture_output=True,
            timeout=GIT_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        message = f"git {arguments[0]} took longer than {GIT_TIMEOUT_SECONDS} seconds"

        raise GitError(message, NEXT_STEP_GIT_HANGS) from error

    if completed.returncode not in {0, accepted}:
        words = completed.stderr.decode("utf-8", errors="replace").strip()
        message = words or f"git {arguments[0]} ended with {completed.returncode}"

        raise GitError(message, NEXT_STEP_GIT_FAILS)

    return completed.stdout


def git_fields(arguments: Sequence[str]) -> list[str]:
    """Run a git command with ``-z`` and return its fields, NUL by NUL.

    Parameters
    ----------
    arguments
        The arguments after ``git``, ``-z`` among them.

    Returns
    -------
    list[str]
        The fields, without the empty one after the last NUL.
    """
    output = run_git(arguments).decode("utf-8", errors="surrogateescape")

    return [field for field in output.split("\0") if field]


# endregion git

# region Message


@dataclass(frozen=True, slots=True)
class Comments:
    """How git marks the comments of a message, and whether it drops them."""

    prefix: str
    is_dropped: bool


def comments_of_commit() -> Comments:
    """Tell how git marks the comments of the commit at hand, and whether it drops them.

    Returns
    -------
    Comments
        The prefix of core.commentString or core.commentChar, else #,
        and whether git drops the comment lines: always under commit.cleanup strip,
        and under the default cleanup only when the commit opens an editor.
    """
    output = run_git(["config", "--get-regexp", COMMENT_SETTINGS], accepted=GIT_CONFIG_UNSET)
    settings: dict[str, str] = {}

    for line in output.decode("utf-8", errors="replace").split("\n"):
        key, _, value = line.partition(" ")
        if key:
            settings[key] = value

    prefix = settings.get("core.commentstring") or settings.get("core.commentchar") or "auto"
    cleanup = settings.get("commit.cleanup", "default")
    # git commit -m and -F keep the comment lines, and git tells the hooks by GIT_EDITOR.
    is_edited = os.environ.get("GIT_EDITOR") != NO_EDITOR

    # With auto, git takes a character that the message does not use, # first of all.
    return Comments(
        prefix=COMMENT_CHARACTER if prefix == "auto" else prefix,
        is_dropped=cleanup == "strip" or (cleanup == "default" and is_edited),
    )


def is_comment(line: str, comments: Comments) -> bool:
    """Tell whether git drops a line of a message as a comment.

    Parameters
    ----------
    line
        One line of the message.
    comments
        How git marks the comments, and whether it drops them.

    Returns
    -------
    bool
        True for a comment line that git drops.
    """
    # git drops every line that starts with the comment prefix,
    # such as the files of git status, which it writes as # and a tab.
    return comments.is_dropped and line.startswith(comments.prefix)


def read_message(message: Path) -> str:
    """Read the file of a commit message as bytes, and decode them as UTF-8.

    Parameters
    ----------
    message
        The file of the commit message, as the commit-msg hook gets it.

    Returns
    -------
    str
        The text, with each carriage return where the file holds it.

    Raises
    ------
    UsageError
        When the file cannot be read: it is missing, a folder, or closed to this user.
    """
    try:
        # read_text would turn a lone carriage return into a newline, which git keeps in its line.
        content = message.read_bytes()
    except OSError as error:
        problem = (
            f"cannot read the message file {message}: {error.strerror or error};"
            " give the file that holds the message"
        )

        raise UsageError(problem) from error

    return content.decode("utf-8", errors="replace")


def message_lines(text: str, comments: Comments) -> list[tuple[int, str]]:
    """Return the lines of a message that git keeps, each with its number in the file.

    Parameters
    ----------
    text
        The message as the hook reads it, comments and the diff of --verbose included.
    comments
        How git marks the comments, and whether it drops them.

    Returns
    -------
    list[tuple[int, str]]
        The number of each line, from 1, and the line without the spaces at its end,
        for every line above the diff that is no comment.
    """
    scissors = f"{comments.prefix} {SCISSORS}"
    lines: list[tuple[int, str]] = []

    # git ends a line at a newline alone; splitlines would also end it
    # at a carriage return, a form feed or U+2028.
    for number, line in enumerate(text.split("\n"), start=1):
        if line == scissors:
            break
        if not is_comment(line, comments):
            lines.append((number, line.rstrip()))

    return lines


def kept_lines(text: str, comments: Comments) -> list[str]:
    """Return the lines of a message that git keeps.

    Parameters
    ----------
    text
        The message as the hook reads it, comments and the diff of --verbose included.
    comments
        How git marks the comments, and whether it drops them.

    Returns
    -------
    list[str]
        The lines without comments, without the diff, and without blank lines at the end.
    """
    lines = [line for _, line in message_lines(text, comments)]

    while lines and not lines[-1]:
        lines.pop()

    return lines


# endregion Message

# region Trailers


def paragraphs(lines: Sequence[str]) -> list[list[str]]:
    """Split lines into paragraphs at the blank lines.

    Parameters
    ----------
    lines
        The lines of a message.

    Returns
    -------
    list[list[str]]
        Each paragraph, with at least one line.
    """
    groups: list[list[str]] = [[]]

    for line in lines:
        if line.strip():
            groups[-1].append(line)
        elif groups[-1]:
            groups.append([])

    return [group for group in groups if group]


def is_continuation(line: str) -> bool:
    """Tell whether a line goes on with the trailer above it, by its indent.

    Parameters
    ----------
    line
        One line of a paragraph.

    Returns
    -------
    bool
        True when the line opens with a space or a tab.
    """
    return line[:1].isspace()


def trailer_key(line: str) -> str:
    """Return the key of a trailer line, in lower case.

    Parameters
    ----------
    line
        A line such as ``Why: the reason``.

    Returns
    -------
    str
        The key, such as ``why``.
    """
    return line.split(":", 1)[0].lower()


def trailer_share(paragraph: Sequence[str]) -> tuple[int, int]:
    """Count the lines of a paragraph that look like trailers.

    Parameters
    ----------
    paragraph
        The lines of one paragraph.

    Returns
    -------
    tuple[int, int]
        The lines that look like trailers, and all lines but the continuations.
    """
    heads = [line for line in paragraph if not is_continuation(line)]
    trailers = [line for line in heads if TRAILER_LINE_PATTERN.match(line)]

    return len(trailers), len(heads)


def parsed_keys(lines: Sequence[str]) -> list[str]:
    """Return the keys of the trailers that git parses from a message, in their order.

    Parameters
    ----------
    lines
        The kept lines of the message.

    Returns
    -------
    list[str]
        The key of each trailer, in lower case.
    """
    # git log reads the trailers of a commit without the divider of a patch.
    message = "\n".join(lines) + "\n"
    output = run_git(["interpret-trailers", "--parse", "--no-divider"], stdin=message.encode())

    trailers = output.decode("utf-8", errors="replace").split("\n")

    return [trailer_key(line) for line in trailers if line]


def unparsed_lines(paragraph: Sequence[str], keys: Sequence[str]) -> list[str]:
    """Return the lines of the last paragraph that git takes for no trailer.

    Parameters
    ----------
    paragraph
        The last paragraph of the message.
    keys
        The keys of the trailers that git parsed, in their order.

    Returns
    -------
    list[str]
        Each line that is neither a parsed trailer nor its continuation.
    """
    remaining = list(keys)
    lines: list[str] = []

    for line in paragraph:
        if is_continuation(line):
            continue
        if TRAILER_LINE_PATTERN.match(line) and remaining and remaining[0] == trailer_key(line):
            remaining.pop(0)
        else:
            lines.append(line)

    return lines


def check_trailers(message: Path) -> list[str]:
    """Find the lines of a message that look like trailers but are none that git parses.

    Parameters
    ----------
    message
        The file of the commit message, as the commit-msg hook gets it.

    Returns
    -------
    list[str]
        One finding per line.
    """
    lines = kept_lines(read_message(message), comments_of_commit())
    # The first paragraph is the subject, which carries no trailer.
    body = paragraphs(lines)[1:]

    if not body:
        return []

    findings: list[str] = []

    # A paragraph of trailers before the last one is lost: git reads the last paragraph alone.
    for block in body[:-1]:
        trailers, heads = trailer_share(block)
        if trailers and trailers == heads:
            findings.append(f"a blank line parts this trailer from the last paragraph: {block[0]}")

    # Prose may hold a line such as "Note: x",
    # but a paragraph of trailers holds at least as many trailers as other lines.
    trailers, heads = trailer_share(body[-1])

    if trailers and trailers >= heads - trailers:
        findings.extend(
            f"git takes this line for no trailer: {line}"
            for line in unparsed_lines(body[-1], parsed_keys(lines))
        )

    return findings


# endregion Trailers

# region Line length


def long_lines(lines: Sequence[tuple[int, str]]) -> list[str]:
    """Find the lines that are longer than LINE_LENGTH_LIMIT characters and hold no URL.

    Parameters
    ----------
    lines
        The number of each line in the file of the message, and the line.

    Returns
    -------
    list[str]
        One finding per line, with its number and its length.
    """
    # len counts characters, so a letter of two or more bytes in UTF-8 counts once.
    return [
        f"line {number} has {len(line)} characters: {line}"
        for number, line in lines
        if len(line) > LINE_LENGTH_LIMIT and not URL_PATTERN.search(line)
    ]


def check_line_length(message: Path) -> list[str]:
    """Find the lines of a message that are longer than LINE_LENGTH_LIMIT characters.

    Parameters
    ----------
    message
        The file of the commit message, as the commit-msg hook gets it.

    Returns
    -------
    list[str]
        One finding per line, with its number in the file.
    """
    return long_lines(message_lines(read_message(message), comments_of_commit()))


# endregion Line length

# region References


@dataclass(frozen=True, slots=True)
class Move:
    """A path that a commit renames or deletes."""

    old: str
    new: str | None

    def what_happens(self) -> str:
        """Say what the commit does to the old path.

        Returns
        -------
        str
            Such as ``renames to docs/new.md``, or ``deletes``.
        """
        return f"renames to {self.new}" if self.new else "deletes"


def staged_moves() -> list[Move]:
    """Return the paths that the staged commit renames or deletes.

    Returns
    -------
    list[Move]
        Each rename and each deletion of the index against HEAD.
    """
    fields = git_fields(["diff", "--cached", "--name-status", "-M", "-z"])
    moves: list[Move] = []
    position = 0

    while position < len(fields):
        status = fields[position]
        # A rename or a copy gives two paths, the other changes one.
        if status.startswith(("R", "C")):
            if status.startswith("R"):
                moves.append(Move(fields[position + 1], fields[position + 2]))
            position += 3
        else:
            if status == "D":
                moves.append(Move(fields[position + 1], None))
            position += 2

    return moves


def ere_pattern(name: str) -> str:
    """Return a pattern for git grep that finds a path or a name standing alone.

    Parameters
    ----------
    name
        A path, such as ``docs/old.md``, or a file name.

    Returns
    -------
    str
        An extended regular expression for ``git grep -E``.
    """
    # Python 3.11 and older take no backslash inside the braces of an f-string.
    escaped = ERE_SPECIAL_PATTERN.sub(r"\\\1", name)

    return f"{NAME_BEFORE}{escaped}{NAME_AFTER}"


def names_of(move: Move, indexed_names: set[str]) -> list[str]:
    """Return what a reference to the old path of a move can say.

    Parameters
    ----------
    move
        The rename or the deletion.
    indexed_names
        The file names that the index still holds after the commit.

    Returns
    -------
    list[str]
        The old path, and its file name when no file of the index still has that name.
    """
    names = [move.old]
    name = PurePosixPath(move.old).name

    if name != move.old and name not in indexed_names:
        names.append(name)

    return names


def references_to(name: str, move: Move, excludes: Sequence[str]) -> list[str]:
    """Find the lines of the index that name a path or a name.

    Parameters
    ----------
    name
        The old path, or its file name.
    move
        The move it belongs to, for the finding.
    excludes
        The globs of the files that may name it.

    Returns
    -------
    list[str]
        One finding per line, as ``FILE:LINE: ...``.
    """
    pathspecs = [":(top)", *(f":(top,exclude,glob){glob}" for glob in excludes)]
    arguments = ["grep", "--cached", "-I", "-n", "-z", "-E", "-e", ere_pattern(name)]
    output = run_git([*arguments, "--", *pathspecs], accepted=GIT_GREP_NO_MATCH)

    # With -z, each match is PATH NUL LINE NUL TEXT, and a newline ends it.
    findings: list[str] = []

    # splitlines would also split at a form feed or a vertical tab inside the text.
    for match in output.decode("utf-8", errors="surrogateescape").split("\n"):
        if not match:
            continue
        path, number, _ = match.split("\0", 2)
        findings.append(f"{path}:{number}: names {name}, which this commit {move.what_happens()}")

    return findings


def check_references(excludes: Sequence[str]) -> list[str]:
    """Find the files of the index that name a path the commit renames or deletes.

    Parameters
    ----------
    excludes
        The globs of the files that may name an old path, besides the changelog.

    Returns
    -------
    list[str]
        One finding per line that names an old path.
    """
    moves = staged_moves()

    if not moves:
        return []

    indexed_names = {PurePosixPath(path).name for path in git_fields(["ls-files", "-z", ":/"])}
    findings: list[str] = []
    # A line that names the old path also names its file name: it counts once per move.
    seen: set[tuple[str, str]] = set()

    for move in moves:
        for name in names_of(move, indexed_names):
            for finding in references_to(name, move, [*REFERENCE_EXCLUDES, *excludes]):
                place = (finding.split(": ", 1)[0], move.old)
                if place not in seen:
                    seen.add(place)
                    findings.append(finding)

    return findings


# endregion References

# region Index


def is_temporary(path: str) -> bool:
    """Tell whether a path names a file that an editor or a merge leaves behind.

    Parameters
    ----------
    path
        A path of the repository.

    Returns
    -------
    bool
        True when its file name matches one of TEMPORARY_PATTERNS.
    """
    name = PurePosixPath(path).name

    return any(fnmatch.fnmatchcase(name, pattern) for pattern in TEMPORARY_PATTERNS)


def check_temporary() -> list[str]:
    """Find the temporary files that the staged commit adds.

    Returns
    -------
    list[str]
        The paths of the temporary files that the commit adds or renames into place.
    """
    added = git_fields(["diff", "--cached", "--name-only", "--diff-filter=AR", "-z"])

    return [path for path in added if is_temporary(path)]


def untracked_paths() -> list[str]:
    """Return the untracked files that git does not ignore.

    Returns
    -------
    list[str]
        Their paths, relative to the top of the repository.
    """
    return git_fields(["ls-files", "--others", "--exclude-standard", "-z", "--", ":/"])


# endregion Index

# region Commands


def write_lines(stream: TextIO, lines: Sequence[str]) -> None:
    """Write lines to a stream, each with its newline.

    Parameters
    ----------
    stream
        stdout for data, stderr for messages.
    lines
        The lines.
    """
    stream.writelines(f"{line}\n" for line in lines)


def report(*lines: str) -> None:
    """Print a message to stderr, each line prefixed with the name of the program.

    Parameters
    ----------
    *lines
        The lines of the message.
    """
    write_lines(sys.stderr, [f"{PROGRAM}: {line}" for line in lines])


def command_trailers(arguments: Sequence[str]) -> int:
    """Check the trailers of the message in a file.

    Parameters
    ----------
    arguments
        The file of the message, alone.

    Returns
    -------
    int
        0, or CC_ERR_TRAILERS when a finding comes up.

    Raises
    ------
    UsageError
        When the command line names no file, or more than one, or a file that cannot be read.
    """
    if len(arguments) != 1:
        message = "trailers takes one file: the message of the commit"

        raise UsageError(message)

    findings = check_trailers(Path(arguments[0]))

    if not findings:
        return 0

    write_lines(sys.stdout, findings)
    report(
        "write each trailer as Key: value, with a key of one word,",
        "go on over lines indented by two spaces, and keep the trailers in one block at the end",
    )

    return CC_ERR_TRAILERS


def command_line_length(arguments: Sequence[str]) -> int:
    """Check the length of every line of the message in a file.

    Parameters
    ----------
    arguments
        The file of the message, alone.

    Returns
    -------
    int
        0, or CC_ERR_LINE_LENGTH when a finding comes up.

    Raises
    ------
    UsageError
        When the command line names no file, or more than one, or a file that cannot be read.
    """
    if len(arguments) != 1:
        message = "line-length takes one file: the message of the commit"

        raise UsageError(message)

    findings = check_line_length(Path(arguments[0]))

    if not findings:
        return 0

    write_lines(sys.stdout, findings)
    report(
        f"break each line at a pause, so that none is longer than {LINE_LENGTH_LIMIT} characters;",
        "only a line that holds a URL may run past",
    )

    return CC_ERR_LINE_LENGTH


def parse_excludes(arguments: Sequence[str]) -> list[str]:
    """Parse the options of the references command.

    Parameters
    ----------
    arguments
        The command line after ``references``.

    Returns
    -------
    list[str]
        The globs of ``--exclude GLOB`` and ``--exclude=GLOB``.

    Raises
    ------
    UsageError
        When an option is unknown or has no value.
    """
    excludes: list[str] = []
    position = 0

    while position < len(arguments):
        argument = arguments[position]
        if argument == "--exclude":
            if position + 1 == len(arguments):
                message = "--exclude needs a glob, such as docs/history/*.md"

                raise UsageError(message)
            excludes.append(arguments[position + 1])
            position += 2
        elif argument.startswith("--exclude="):
            excludes.append(argument.removeprefix("--exclude="))
            position += 1
        else:
            message = f"references takes no argument {argument}"

            raise UsageError(message)

    return excludes


def command_references(arguments: Sequence[str]) -> int:
    """Check that no file of the index names a path the commit renames or deletes.

    Parameters
    ----------
    arguments
        The options ``--exclude GLOB``.

    Returns
    -------
    int
        0, or CC_ERR_REFERENCES when a finding comes up.
    """
    findings = check_references(parse_excludes(arguments))

    if not findings:
        return 0

    write_lines(sys.stdout, findings)
    report(
        "point each reference at the new path, or take it out;",
        "a file that names the old path on purpose goes into --exclude in .pre-commit-config.yaml",
    )

    return CC_ERR_REFERENCES


def command_temporary(arguments: Sequence[str]) -> int:
    """Check that the commit adds no temporary file.

    Parameters
    ----------
    arguments
        Nothing.

    Returns
    -------
    int
        0, or CC_ERR_TEMPORARY when the commit adds one.

    Raises
    ------
    UsageError
        When the command line holds anything.
    """
    if arguments:
        message = "temporary takes no argument"

        raise UsageError(message)

    found = check_temporary()

    if not found:
        return 0

    write_lines(sys.stdout, found)
    report(
        "take each one out with git rm --cached -- FILE,",
        "and put its pattern into .gitignore, so git leaves it alone",
    )

    return CC_ERR_TEMPORARY


def command_untracked(arguments: Sequence[str]) -> int:
    """List the untracked files, which the commit leaves out.

    Parameters
    ----------
    arguments
        Nothing.

    Returns
    -------
    int
        Always 0: an untracked file may belong to other work.

    Raises
    ------
    UsageError
        When the command line holds anything.
    """
    if arguments:
        message = "untracked takes no argument"

        raise UsageError(message)

    paths = untracked_paths()
    write_lines(sys.stdout, paths[:UNTRACKED_SHOWN])

    if len(paths) > UNTRACKED_SHOWN:
        # stdout holds paths alone, so the count of the rest is a message.
        report(f"and {len(paths) - UNTRACKED_SHOWN} more untracked files")

    return 0


def main(arguments: Sequence[str]) -> int:
    """Run the command that the command line names.

    Parameters
    ----------
    arguments
        The command line, without the name of the program.

    Returns
    -------
    int
        The exit status.
    """
    commands: dict[str, Callable[[Sequence[str]], int]] = {
        "trailers": command_trailers,
        "line-length": command_line_length,
        "references": command_references,
        "temporary": command_temporary,
        "untracked": command_untracked,
    }
    first = arguments[0] if arguments else ""

    if first in {"-h", "--help"}:
        sys.stdout.write(HELP)

        return 0

    if first == "--version":
        sys.stdout.write(f"{PROGRAM} {VERSION}\n")

        return 0

    command = commands.get(first)

    if command is None:
        problem = f"unknown command: {first}" if first else "give a command"
        report(problem, "see: commit-checks --help")

        return CC_ERR_USAGE

    try:
        return command(arguments[1:])
    except UsageError as error:
        report(str(error), "see: commit-checks --help")

        return CC_ERR_USAGE
    except GitError as error:
        report(f"git failed: {error}", error.next_step)

        return CC_ERR_GIT


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

# endregion Commands
