"""Test the patterns that references hands to git grep."""

from types import ModuleType

import pytest
from hypothesis import given
from hypothesis import strategies as st

# The characters that the extended regular expressions of git grep take as special.
ERE_SPECIAL_CHARACTERS = frozenset(".[]()*+?{}|^$\\")


@given(name=st.text(alphabet=st.characters(exclude_categories=["Cs"]), min_size=1, max_size=40))
def test_every_special_character_of_a_name_and_nothing_else_gets_a_backslash(
    commit_checks: ModuleType, name: str
) -> None:
    """Check that git grep looks for a path as it is, whatever characters it holds."""
    pattern = commit_checks.ere_pattern(name)

    middle = pattern.removeprefix(commit_checks.NAME_BEFORE).removesuffix(commit_checks.NAME_AFTER)
    expected = "".join(
        f"\\{character}" if character in ERE_SPECIAL_CHARACTERS else character
        for character in name
    )
    assert middle == expected


@pytest.mark.parametrize(
    ("indexed_paths", "expected"),
    [
        ({"bin/tool.sh"}, True),
        ({"bin/tool.py", "README.md"}, True),
        ({"bin/tool"}, False),
        ({"bin/toolkit.sh"}, False),
        ({"bin/tool.sh/inner"}, False),
        ({"other/tool.sh"}, False),
    ],
)
def test_took_extension_should_be_true_when_the_index_holds_the_old_path_and_an_extension(
    commit_checks: ModuleType, indexed_paths: set[str], *, expected: bool
) -> None:
    """Check that the old path took an extension only with a dot and a name of no folder."""
    # Arrange
    move = commit_checks.Move("bin/tool", None)

    # Act
    result = commit_checks.took_extension(move, indexed_paths)

    # Assert
    assert result is expected


def test_names_of_should_leave_out_the_file_name_when_the_path_took_an_extension(
    commit_checks: ModuleType,
) -> None:
    """Check that a program renamed to NAME.sh keeps NAME, which a search would find everywhere."""
    # Arrange
    move = commit_checks.Move("bin/tool", None)

    # Act
    names = commit_checks.names_of(move, set(), has_extension=True)

    # Assert
    assert names == ["bin/tool"]


def test_ere_pattern_should_end_without_a_dot_when_no_dot_may_follow(
    commit_checks: ModuleType,
) -> None:
    """Check that the pattern of a path that took an extension leaves out its dot."""
    # Arrange: the path of a program that took an extension.

    # Act
    pattern = commit_checks.ere_pattern("bin/tool", is_dot_after=False)

    # Assert
    assert pattern.endswith(commit_checks.NAME_AFTER_WITHOUT_DOT)
