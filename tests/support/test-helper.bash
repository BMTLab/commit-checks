# shellcheck shell=bash

# Give the tests of commit-checks a throwaway repository and the script to run.
#
# The repository has a git config of its own, so the config of the machine changes nothing.
# It declares the trailer keys that the tests use, such as Why and Verified,
# as the git config of a committer may: git then still reads a block of trailers
# that holds one broken line, and drops that line alone.

COMMIT_CHECKS="${BATS_TEST_DIRNAME}/../../commit-checks.py"

#######################################
# Read the value of an exit code from the constants of commit-checks.py.
#
# Arguments:
#   1: The name of the code, such as CC_ERR_USAGE.
#
# Outputs:
#   The number, to stdout.
#######################################
function exit_code() {
  sed -n "s/^$1: Final = //p" "${COMMIT_CHECKS}"
}

#######################################
# Make an empty repository in BATS_TEST_TMPDIR and enter it.
#
# Globals:
#   REPOSITORY: Set to the path of the repository.
#   GIT_CONFIG_GLOBAL, GIT_CONFIG_NOSYSTEM: Exported, to keep out the configs of the machine.
#######################################
function make_repository() {
  local key

  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
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

### End
