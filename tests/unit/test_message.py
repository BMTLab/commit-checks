"""Test how commit-checks reads the lines of a message, as git keeps them."""

from types import ModuleType

from hypothesis import given
from hypothesis import strategies as st

SCISSORS_LINES = (
    "# ------------------------ >8 ------------------------",
    "; ------------------------ >8 ------------------------",
)
# A line of a message: any text without a newline, or a line that the hooks look for,
# such as a comment, a file of git status or the scissors of git commit --verbose.
LINES = st.one_of(
    st.text(alphabet=st.characters(exclude_characters="\n"), max_size=90),
    st.sampled_from(["", "#", "# a comment", "#\tmodified:   main.py", "; a comment", "Why: x  "]),
    st.sampled_from(SCISSORS_LINES),
)
PREFIXES = st.sampled_from(["#", ";"])


@given(lines=st.lists(LINES, max_size=12), prefix=PREFIXES, is_dropped=st.booleans())
def test_each_kept_line_is_its_line_of_the_file_without_the_spaces_at_its_end(
    commit_checks: ModuleType, lines: list[str], prefix: str, is_dropped: bool
) -> None:
    """Check that the numbers rise and that each names the line it keeps."""
    text = "\n".join(lines)
    comments = commit_checks.Comments(prefix=prefix, is_dropped=is_dropped)

    kept = commit_checks.message_lines(text, comments)

    source = text.split("\n")
    numbers = [number for number, _ in kept]
    assert numbers == sorted(set(numbers))
    assert all(line == source[number - 1].rstrip() for number, line in kept)


@given(lines=st.lists(LINES, max_size=12), prefix=PREFIXES, is_dropped=st.booleans())
def test_no_line_from_the_scissors_on_is_kept(
    commit_checks: ModuleType, lines: list[str], prefix: str, is_dropped: bool
) -> None:
    """Check that the scissors line and the diff of --verbose below it stay out."""
    text = "\n".join(lines)
    comments = commit_checks.Comments(prefix=prefix, is_dropped=is_dropped)
    scissors = f"{prefix} {commit_checks.SCISSORS}"

    kept = commit_checks.message_lines(text, comments)

    source = text.split("\n")
    end = source.index(scissors) if scissors in source else len(source)
    assert all(number <= end for number, _ in kept)


@given(lines=st.lists(LINES, max_size=12), prefix=PREFIXES)
def test_a_dropped_comment_never_comes_back(
    commit_checks: ModuleType, lines: list[str], prefix: str
) -> None:
    """Check that no kept line starts with the prefix, where git drops the comments."""
    comments = commit_checks.Comments(prefix=prefix, is_dropped=True)

    kept = commit_checks.message_lines("\n".join(lines), comments)

    assert not any(line.startswith(prefix) for _, line in kept)


@given(lines=st.lists(LINES, max_size=12), prefix=PREFIXES)
def test_every_line_above_the_scissors_stays_where_git_keeps_the_comments(
    commit_checks: ModuleType, lines: list[str], prefix: str
) -> None:
    """Check that git commit -m and -F lose no line above the scissors."""
    text = "\n".join(lines)
    comments = commit_checks.Comments(prefix=prefix, is_dropped=False)
    scissors = f"{prefix} {commit_checks.SCISSORS}"

    kept = commit_checks.message_lines(text, comments)

    source = text.split("\n")
    end = source.index(scissors) if scissors in source else len(source)
    assert len(kept) == end


@given(lines=st.lists(st.sampled_from(["", " ", "\t", "a", "Why: b", "  c"]), max_size=15))
def test_paragraphs_keep_every_line_that_is_not_blank(
    commit_checks: ModuleType, lines: list[str]
) -> None:
    """Check that the paragraphs hold the lines that are not blank, in order, and no empty one."""
    groups = commit_checks.paragraphs(lines)

    assert [line for group in groups for line in group] == [line for line in lines if line.strip()]
    assert all(groups)
