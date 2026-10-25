#!/usr/bin/env bats
# shellcheck shell=bash

# Test commit-checks in throwaway repositories, as the git hooks of pre-commit run it.

bats_require_minimum_version 1.11.0

# shellcheck source=../support/test-helper.bash
source "${BATS_TEST_DIRNAME}/../support/test-helper.bash"

# region Setup

#######################################
# Give the test a scratch home and an empty repository, and enter the repository.
#######################################
function setup() {
  sandbox_setup
  make_repository
  # A commit with an editor is the default; a test without one sets GIT_EDITOR=: as git does.
  unset GIT_EDITOR
  # A misspelled name, such as that of an exit code, fails the test.
  set -o nounset
}

# endregion Setup

# region Sandbox

@test "git and the script see a scratch home of the test, not the home of the user" {
  # Arrange: the scratch home of setup.

  # Act
  run --separate-stderr printenv HOME XDG_CONFIG_HOME

  # Assert
  ((status == 0))
  [[ "${output}" == "${BATS_TEST_TMPDIR}/home"$'\n'"${BATS_TEST_TMPDIR}/home/.config" ]]
}

# endregion Sandbox

# region Trailers

@test "a message whose trailers git parses passes" {
  # Arrange
  local message

  message="$(write_message 'Fix the parser' '' 'Why: the parser lost a line' \
    '  at the end of a file.' 'Verified: make check.' 'Co-Authored-By: A <a@example.com>')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == 0))
  [[ -z "${output}" ]]
}

@test "a continuation without its indent fails, and names the line" {
  # Arrange
  local message

  message="$(write_message 'Fix the parser' '' 'Why: the parser lost a line' \
    'at the end of a file.' 'Verified: make check.')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == CC_ERR_TRAILERS))
  [[ "${output}" == 'git takes this line for no trailer: at the end of a file.' ]]
}

@test "a key of two words fails, and names the line" {
  # Arrange
  local message

  message="$(write_message 'Fix the parser' '' 'Why: a reason.' 'Tested on: Ubuntu.' \
    'Verified: make check.')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == CC_ERR_TRAILERS))
  [[ "${output}" == 'git takes this line for no trailer: Tested on: Ubuntu.' ]]
}

@test "a blank line inside the trailers fails" {
  # Arrange
  local message

  message="$(write_message 'Fix the parser' '' 'Why: a reason.' '' 'Verified: make check.')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == CC_ERR_TRAILERS))
  [[ "${output}" == *'a blank line parts this trailer from the last paragraph: Why: a reason.'* ]]
}

@test "a subject alone passes" {
  # Arrange
  local message

  message="$(write_message 'Fix a typo in the README')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == 0))
}

@test "prose with a colon in its last paragraph passes" {
  # Arrange
  local message

  message="$(write_message 'Fix the parser' '' 'The parser read one line too few,' \
    'so the last one went missing.' 'Note: the old files read fine.')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == 0))
}

@test "comments and the diff of --verbose stay out of the check" {
  # Arrange
  local message

  message="$(write_message 'Fix the parser' '' 'Why: a reason.' \
    '# Please enter the commit message for your changes.' \
    '# ------------------------ >8 ------------------------' 'Broken: line' 'not a trailer')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == 0))
}

@test "the status that git writes under the message in an editor stays out of the check" {
  # Arrange
  local message

  # git writes each file of the status as # and a tab, without a space.
  message="$(write_message 'Fix the parser' '' 'Why: a reason.' 'Verified: make check.' '' \
    '# Please enter the commit message for your changes.' '#' \
    '# Changes to be committed:' $'#\tmodified:   main.py' '#')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  ((status == 0))
  [[ -z "${output}" ]]
}

# endregion Trailers

# region Line length

#######################################
# Check that a line of 72 characters passes, however many bytes they take.
#
# Arguments:
#   1: The character that fills the line, such as a or ж.
#######################################
function a_line_of_72_characters_passes() {
  # Arrange
  local line message

  line="$(repeat_character "$1" 72)"
  message="$(write_message 'Fix the parser' '' "${line}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == 0))
  [[ -z "${output}" ]]
}

#######################################
# Check that a line of 73 characters fails, and that the finding names it.
#
# Arguments:
#   1: The character that fills the line, such as a or ж.
#######################################
function a_line_of_73_characters_fails() {
  # Arrange
  local line message

  line="$(repeat_character "$1" 73)"
  message="$(write_message 'Fix the parser' '' "${line}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == CC_ERR_LINE_LENGTH))
  [[ "${output}" == "line 3 has 73 characters: ${line}" ]]
}

# A Cyrillic letter takes two bytes in UTF-8, and still counts as one character.
bats_test_function --description 'a line of 72 Latin letters passes' \
  -- a_line_of_72_characters_passes 'a'
bats_test_function --description 'a line of 72 Cyrillic letters passes' \
  -- a_line_of_72_characters_passes 'ж'
bats_test_function --description 'a line of 73 Latin letters fails, and names the line' \
  -- a_line_of_73_characters_fails 'a'
bats_test_function --description 'a line of 73 Cyrillic letters fails, and names the line' \
  -- a_line_of_73_characters_fails 'ж'

#######################################
# Check that a character which Python takes for a line break, but git does not,
# leaves its line whole, so that the line fails when it is too long.
#
# Arguments:
#   1: The character inside the line, such as a form feed.
#######################################
function a_break_that_git_keeps_leaves_the_line_whole() {
  # Arrange
  local start end line message

  start="$(repeat_character 'a' 60)"
  end="$(repeat_character 'b' 40)"
  line="${start}$1${end}"
  message="$(write_message 'Fix the parser' '' "${line}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == CC_ERR_LINE_LENGTH))
  [[ "${output}" == "line 3 has 101 characters: ${line}" ]]
}

bats_test_function --description 'a form feed inside a line leaves the line whole' \
  -- a_break_that_git_keeps_leaves_the_line_whole $'\f'
bats_test_function --description 'a carriage return inside a line leaves the line whole' \
  -- a_break_that_git_keeps_leaves_the_line_whole $'\r'

@test "a subject of 73 characters fails" {
  # Arrange
  local subject message

  subject="$(repeat_character 'A' 73)"
  message="$(write_message "${subject}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == CC_ERR_LINE_LENGTH))
  [[ "${output}" == "line 1 has 73 characters: ${subject}" ]]
}

@test "each line past the limit is named by its number" {
  # Arrange
  local line message

  line="$(repeat_character 'a' 80)"
  message="$(write_message 'Fix the parser' '' "${line}" 'A short line.' "${line}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == CC_ERR_LINE_LENGTH))
  [[ "${output}" == "line 3 has 80 characters: ${line}"$'\n'"line 5 has 80 characters: ${line}" ]]
}

@test "a line that holds a URL may run past the limit" {
  # Arrange
  local url message

  url='https://github.com/BMTLab/commit-checks/blob/main/README.md#how-it-works-in-full'
  message="$(write_message 'Fix the parser' '' 'Why: the parser lost a line.' "See: ${url}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == 0))
}

@test "the spaces at the end of a line do not count, since git drops them" {
  # Arrange
  local line message

  line="$(repeat_character 'a' 72)"
  message="$(write_message 'Fix the parser' '' "${line}   ")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == 0))
}

@test "a long comment line counts under git commit -m or -F, which keep it" {
  # Arrange
  local comment message

  comment="$(repeat_character 'a' 80)"
  comment="# ${comment}"
  message="$(write_message 'Fix the parser' '' "${comment}")"

  # Act
  run --separate-stderr env GIT_EDITOR=: "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == CC_ERR_LINE_LENGTH))
  [[ "${output}" == "line 3 has 82 characters: ${comment}" ]]
}

@test "commit.cleanup strip drops the comment lines without an editor too" {
  # Arrange
  local long_text message

  long_text="$(repeat_character 'a' 80)"
  message="$(write_message 'Fix the parser' '' "# ${long_text}")"
  git config commit.cleanup strip

  # Act
  run --separate-stderr env GIT_EDITOR=: "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == 0))
}

@test "core.commentChar names the comment lines" {
  # Arrange
  local long_text message

  long_text="$(repeat_character 'a' 80)"
  message="$(write_message 'Fix the parser' '' "; ${long_text}" \
    '; ------------------------ >8 ------------------------' "+${long_text}")"
  git config core.commentChar ';'

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == 0))
}

@test "a line that starts with # is text where core.commentChar names another character" {
  # Arrange
  local line message

  line="$(repeat_character 'a' 80)"
  line="# ${line}"
  message="$(write_message 'Fix the parser' '' "${line}")"
  git config core.commentChar ';'

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == CC_ERR_LINE_LENGTH))
  [[ "${output}" == "line 3 has 82 characters: ${line}" ]]
}

@test "comments, the status of git and the diff of --verbose stay out of the length check" {
  # Arrange
  local long_text message

  long_text="$(repeat_character 'a' 80)"
  message="$(write_message 'Fix the parser' '' "# ${long_text}" $'#\trenamed:    '"${long_text}" \
    '# ------------------------ >8 ------------------------' "+${long_text}")"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" line-length "${message}"

  # Assert
  ((status == 0))
}

# endregion Line length

# region References

@test "a reference to a renamed file fails, and names the file and the line" {
  # Arrange
  commit_files 'rules/agents.md' 'The rules.' 'README.md' $'# Notes\n\nSee rules/agents.md.'
  git mv -- rules/agents.md rules/environment.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  ((status == CC_ERR_REFERENCES))
  [[ "${output}" == 'README.md:3: names rules/agents.md, which this commit renames to rules/environment.md' ]]
}

@test "a reference to a deleted file fails" {
  # Arrange
  commit_files 'docs/old.md' 'Old text.' 'README.md' 'Read old.md first.'
  git rm -q -- docs/old.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  ((status == CC_ERR_REFERENCES))
  [[ "${output}" == 'README.md:1: names old.md, which this commit deletes' ]]
}

@test "a commit without a rename or a deletion passes" {
  # Arrange
  commit_files 'README.md' 'See notes.md.' 'notes.md' 'Notes.'
  printf 'More notes.\n' >>notes.md
  git add -- notes.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  ((status == 0))
  [[ -z "${output}" ]]
}

@test "a name that another file still has counts only as the full path" {
  # Arrange
  commit_files 'README.md' 'See sub/README.md, or the README.md of each folder.' \
    'sub/README.md' 'Sub.' 'other/README.md' 'Other.'
  git rm -q -- sub/README.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  ((status == CC_ERR_REFERENCES))
  [[ "${output}" == 'README.md:1: names sub/README.md, which this commit deletes' ]]
}

@test "a longer name that holds the old one is no reference" {
  # Arrange
  commit_files 'old.md' 'Old.' 'README.md' 'See my-old.md and old.mdx.'
  git rm -q -- old.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  ((status == 0))
}

@test "CHANGELOG.md may name the old path" {
  # Arrange
  commit_files 'old.md' 'Old.' 'CHANGELOG.md' 'Renamed old.md to new.md.'
  git mv -- old.md new.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  ((status == 0))
}

@test "--exclude leaves a file out of the search" {
  # Arrange
  commit_files 'old.md' 'Old.' 'docs/history.md' 'Once there was old.md.'
  git rm -q -- old.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references --exclude 'docs/*.md'

  # Assert
  ((status == 0))
}

# endregion References

# region Temporary and untracked files

#######################################
# Check that a commit which adds a temporary file fails, and names it.
#
# Arguments:
#   1: The name of the file, such as notes.orig.
#######################################
function a_temporary_file_fails() {
  # Arrange
  local -r name="$1"

  commit_files 'README.md' 'Readme.'
  printf 'left behind\n' >"${name}"
  git add -f -- "${name}"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" temporary

  # Assert
  ((status == CC_ERR_TEMPORARY))
  [[ "${output}" == "${name}" ]]
}

for temporary_name in notes.orig fix.rej config.bak .notes.md.swp notes.md~; do
  bats_test_function --description "a commit that adds ${temporary_name} fails" \
    -- a_temporary_file_fails "${temporary_name}"
done

@test "a commit of ordinary files passes the temporary check" {
  # Arrange
  commit_files 'README.md' 'Readme.'
  printf 'code\n' >main.sh
  git add -- main.sh

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" temporary

  # Assert
  ((status == 0))
}

@test "untracked lists the files that the commit leaves out, and passes" {
  # Arrange
  commit_files 'README.md' 'Readme.'
  printf 'draft\n' >draft.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" untracked

  # Assert
  ((status == 0))
  [[ "${output}" == 'draft.md' ]]
}

@test "untracked leaves out the files that .gitignore names" {
  # Arrange
  commit_files '.gitignore' '*.log'
  printf 'noise\n' >build.log

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" untracked

  # Assert
  ((status == 0))
  [[ -z "${output}" ]]
}

# endregion Temporary and untracked files

# region Error model

#######################################
# Check that a wrong command line ends with CC_ERR_USAGE, and says what is wrong.
#
# Arguments:
#   1: A part of the message on stderr.
#   2...: The command line.
#######################################
function a_wrong_command_line_ends_with_usage() {
  # Arrange
  local -r expected="$1"
  local -ar command_line=("${@:2}")

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" "${command_line[@]}"

  # Assert
  ((status == CC_ERR_USAGE))
  [[ "${stderr}" == *"${expected}"* ]]
}

bats_test_function --description 'an unknown command ends with CC_ERR_USAGE' \
  -- a_wrong_command_line_ends_with_usage 'unknown command: lint' lint
bats_test_function --description 'trailers without a file ends with CC_ERR_USAGE' \
  -- a_wrong_command_line_ends_with_usage 'trailers takes one file' trailers
bats_test_function --description 'line-length without a file ends with CC_ERR_USAGE' \
  -- a_wrong_command_line_ends_with_usage 'line-length takes one file' line-length
bats_test_function --description '--exclude without a glob ends with CC_ERR_USAGE' \
  -- a_wrong_command_line_ends_with_usage '--exclude needs a glob' references --exclude

@test "outside a repository, a check ends with CC_ERR_GIT" {
  # Arrange
  cd -- "${BATS_TEST_TMPDIR}" || return
  rm -rf -- "${REPOSITORY}"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" untracked

  # Assert
  ((status == CC_ERR_GIT))
  [[ "${stderr}" == *'run commit-checks inside a git repository'* ]]
}

@test "every exit code stands in the card, the help and the README" {
  # Arrange
  local name value help_text
  local -a violations=()

  help_text="$("${COMMIT_CHECKS}" --help)"

  # Act
  for name in "${EXIT_CODE_NAMES[@]}"; do
    value="${!name}"
    if ! grep -qE "^  ${value} ${name}[,.]$" "${COMMIT_CHECKS}"; then
      violations+=("${name}: missing from the card")
    fi
    if [[ "${help_text}" != *"${value}  ${name}:"* ]]; then
      violations+=("${name}: missing from --help")
    fi
    if ! grep -qE "^\| +\`${value}\` +\| +\`${name}\` +\|" "${PROJECT_ROOT}/README.md"; then
      violations+=("${name}: missing from the table of README.md")
    fi
  done

  # Assert
  if ((${#violations[@]} > 0)); then
    printf '%s\n' "${violations[@]}" >&2

    return 1
  fi
}

# endregion Error model

### End
