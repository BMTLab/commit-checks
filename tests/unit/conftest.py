"""Load commit-checks.py as a module, for the unit tests of its functions."""

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

# The script has a hyphen in its name, so it loads by its path rather than by import.
SCRIPT_PATH = Path(__file__).resolve().parents[2] / "commit-checks.py"
MODULE_NAME = "commit_checks"


@pytest.fixture(scope="session")
def commit_checks() -> ModuleType:
    """Load the script once for all the tests, without running its main.

    Returns
    -------
    ModuleType
        The script as a module.

    Raises
    ------
    ImportError
        When Python finds no loader for the script.
    """
    spec = importlib.util.spec_from_file_location(MODULE_NAME, SCRIPT_PATH)
    if spec is None or spec.loader is None:
        message = f"Python finds no loader for {SCRIPT_PATH}"
        raise ImportError(message)

    module = importlib.util.module_from_spec(spec)
    # dataclasses look a class up in sys.modules by the name of its module.
    sys.modules[MODULE_NAME] = module
    spec.loader.exec_module(module)

    return module
