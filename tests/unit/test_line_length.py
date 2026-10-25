"""Test which lines of a message line-length reports."""

from types import ModuleType

import pytest
from hypothesis import given
from hypothesis import strategies as st

LIMIT = 72
# Text without a newline and without the :// of a URL, which may run past the limit.
TEXT = st.characters(exclude_characters="\n:")


@pytest.mark.parametrize(
    ("line", "is_reported"),
    [
        pytest.param("a" * LIMIT, False, id="72 Latin letters"),
        pytest.param("a" * (LIMIT + 1), True, id="73 Latin letters"),
        pytest.param("ж" * LIMIT, False, id="72 Cyrillic letters"),
        pytest.param("ж" * (LIMIT + 1), True, id="73 Cyrillic letters"),
    ],
)
def test_a_line_is_reported_once_it_runs_past_72_characters(
    commit_checks: ModuleType, line: str, is_reported: bool
) -> None:
    """Check both sides of the limit, in letters of one byte and of two."""
    findings = commit_checks.long_lines([(3, line)])

    assert findings == ([f"line 3 has {len(line)} characters: {line}"] if is_reported else [])


@given(lines=st.lists(st.text(alphabet=TEXT, max_size=LIMIT), max_size=8))
def test_no_line_within_the_limit_is_reported(commit_checks: ModuleType, lines: list[str]) -> None:
    """Check that a line of at most 72 characters passes, whatever it holds."""
    findings = commit_checks.long_lines(list(enumerate(lines, start=1)))

    assert findings == []


@given(lines=st.lists(st.text(alphabet=TEXT, min_size=LIMIT + 1, max_size=120), max_size=8))
def test_every_long_line_without_a_url_is_reported(
    commit_checks: ModuleType, lines: list[str]
) -> None:
    """Check that each line past the limit, with no URL in it, gets a finding of its own."""
    findings = commit_checks.long_lines(list(enumerate(lines, start=1)))

    assert len(findings) == len(lines)


@given(start=st.text(alphabet=TEXT, max_size=60), path=st.text(alphabet="abc/-_.", max_size=80))
def test_a_line_with_a_url_is_never_reported(
    commit_checks: ModuleType, start: str, path: str
) -> None:
    """Check that a URL, which cannot break, lets its line run past the limit."""
    line = f"{start} https://example.com/{path}"

    findings = commit_checks.long_lines([(1, line)])

    assert findings == []
