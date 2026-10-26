# shellcheck shell=bash
# shellcheck disable=SC2034 # The tests read the paths and the names that this module sets.

# Give the tests of commit-checks a scratch home, a throwaway repository and the script to run.
#
# Every test file sources it under a `# shellcheck source=` line, rather than with `load`,
# so that ShellCheck follows it and sees what it sets.
# Each test runs in a home of its own, so git reads no file of the user,
# such as the ~/.config/git/ignore that it reads even without a global config.
# The repository has a git config of its own, so the config of the machine changes nothing.
# It declares the trailer keys that the tests use, such as Why and Verified,
# as the git config of a committer may: git then still reads a block of trailers
# that holds one broken line, and drops that line alone.

# region Paths

PROJECT_ROOT="$(readlink -f -- "${BASH_SOURCE[0]%/*}/../..")"
readonly PROJECT_ROOT
readonly COMMIT_CHECKS="${PROJECT_ROOT}/commit-checks.py"

# endregion Paths

# region Exit codes

#######################################
# Read the exit codes of commit-checks.py into readonly variables of the same names,
# such as CC_ERR_USAGE, so that a test compares a status as ((status == CC_ERR_USAGE)).
# A test file turns on nounset, so a misspelled name fails the test.
#
# Globals:
#   COMMIT_CHECKS: The script.
#   EXIT_CODE_NAMES: Set to the names of the codes, in the order of the script.
#   CC_ERR_*: Set, one readonly variable for each code.
#
# Returns:
#   1 when the script holds no code, or a code without a number.
#######################################
function read_exit_codes() {
  local codes name value
  local -a names=()

  codes="$(sed -n 's/^\(CC_ERR_[A-Z_]*\): Final = \(.*\)$/\1 \2/p' "${COMMIT_CHECKS}")"

  if [[ -z "${codes}" ]]; then
    printf 'test-helper: found no exit code in %s\n' "${COMMIT_CHECKS}" >&2

    return 1
  fi

  while IFS=' ' read -r name value; do
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
      printf 'test-helper: the exit code %s is no number: %s\n' "${name}" "${value}" >&2

      return 1
    fi
    declare -gr "${name}=${value}"
    names+=("${name}")
  done <<<"${codes}"

  declare -gra EXIT_CODE_NAMES=("${names[@]}")
}

read_exit_codes

# endregion Exit codes

# region Sandbox

#######################################
# Give the test a home, the folders of XDG, a TMPDIR and a folder of stand-ins
# of its own, so that no test reaches a file of the user.
#
# Globals:
#   FAKE_HOME: Set to the scratch home, which HOME names too.
#   FAKE_BIN: Set to an empty folder for stand-ins, which comes first on PATH.
#   HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME, XDG_DATA_HOME, XDG_STATE_HOME,
#   XDG_RUNTIME_DIR, TMPDIR, PATH: Exported for the scratch home.
#   GIT_CONFIG_GLOBAL, GIT_CONFIG_NOSYSTEM: Exported, so that git reads no config
#     but that of the test repository.
#######################################
function sandbox_setup() {
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"

  export HOME="${FAKE_HOME}"
  # A program that reads a folder of XDG from the environment stays in the home too.
  export XDG_CONFIG_HOME="${FAKE_HOME}/.config"
  export XDG_CACHE_HOME="${FAKE_HOME}/.cache"
  export XDG_DATA_HOME="${FAKE_HOME}/.local/share"
  export XDG_STATE_HOME="${FAKE_HOME}/.local/state"
  # The runtime folder lies outside the home, as /run/user/UID does.
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/run"
  export TMPDIR="${BATS_TEST_TMPDIR}"
  export PATH="${FAKE_BIN}:${PATH}"

  # GIT_CONFIG_GLOBAL wins over HOME, where the environment of the user sets it.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

  mkdir -p -- "${FAKE_HOME}" "${FAKE_BIN}"
  mkdir -m 0700 -- "${XDG_RUNTIME_DIR}"
}

# endregion Sandbox

# region Repository

#######################################
# Make an empty repository in BATS_TEST_TMPDIR and enter it.
#
# Globals:
#   REPOSITORY: Set to the path of the repository.
#######################################
function make_repository() {
  local key

  REPOSITORY="${BATS_TEST_TMPDIR}/repository"

  git init -q -b main -- "${REPOSITORY}"
  cd -- "${REPOSITORY}" || return

  git config user.name 'Test'
  git config user.email 'test@example.com'
  git config commit.gpgSign false

  for key in Why Changed Renamed Breaking Rejected Verified Open See; do
    git config "trailer.${key,,}.key" "${key}"
  done
}

#######################################
# Write files and commit them, as the history that a test starts from.
#
# Arguments:
#   $@: Pairs of a path and its text; the text gets a newline at the end.
#######################################
function commit_files() {
  while (($# > 1)); do
    if [[ "$1" == */* ]]; then
      mkdir -p -- "${1%/*}"
    fi
    printf '%s\n' "$2" >"$1"
    git add -- "$1"
    shift 2
  done

  git commit -q -m 'Start the history of the test'
}

# endregion Repository

# region Messages

#######################################
# Write a commit message into a file of BATS_TEST_TMPDIR.
#
# Arguments:
#   $@: The lines of the message.
#
# Outputs:
#   The path of the file, to stdout.
#######################################
function write_message() {
  local -r message="${BATS_TEST_TMPDIR}/COMMIT_EDITMSG"

  printf '%s\n' "$@" >"${message}"
  printf '%s\n' "${message}"
}

#######################################
# Print one character over and over, as a line of a message.
#
# Arguments:
#   1: The character, such as a or ж.
#   2: How many times the line holds it.
#
# Outputs:
#   The line, to stdout.
#######################################
function repeat_character() {
  local spaces

  printf -v spaces '%*s' "$2" ''
  printf '%s\n' "${spaces// /"$1"}"
}

# endregion Messages

### End
