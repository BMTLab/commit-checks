"""Test the patterns that references hands to git grep."""

from types import ModuleType

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
