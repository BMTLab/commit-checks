#!/usr/bin/env bats

# Test commit-checks in throwaway repositories, as the git hooks of pre-commit run it.

bats_require_minimum_version 1.11.0

load 'support/helpers'

function setup() {
  make_repository
}

# region Trailers

@test "a message whose trailers git parses passes" {
  # Arrange
  local message
  message="$(write_message 'Fix the parser' '' 'Why: the parser lost a line' \
    '  at the end of a file.' 'Verified: make check.' 'Co-Authored-By: A <a@example.com>')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
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
  [[ "${status}" -eq "$(exit_code CC_ERR_TRAILERS)" ]]
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
  [[ "${status}" -eq "$(exit_code CC_ERR_TRAILERS)" ]]
  [[ "${output}" == 'git takes this line for no trailer: Tested on: Ubuntu.' ]]
}

@test "a blank line inside the trailers fails" {
  # Arrange
  local message
  message="$(write_message 'Fix the parser' '' 'Why: a reason.' '' 'Verified: make check.')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_TRAILERS)" ]]
  [[ "${output}" == *'a blank line parts this trailer from the last paragraph: Why: a reason.'* ]]
}

@test "a subject alone passes" {
  # Arrange
  local message
  message="$(write_message 'Fix a typo in the README')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "prose with a colon in its last paragraph passes" {
  # Arrange
  local message
  message="$(write_message 'Fix the parser' '' 'The parser read one line too few,' \
    'so the last one went missing.' 'Note: the old files read fine.')"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers "${message}"

  # Assert
  [[ "${status}" -eq 0 ]]
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
  [[ "${status}" -eq 0 ]]
}

@test "trailers without a file ends with CC_ERR_USAGE" {
  # Act
  run --separate-stderr "${COMMIT_CHECKS}" trailers

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_USAGE)" ]]
  [[ "${stderr}" == *'trailers takes one file'* ]]
}

# endregion Trailers

# region References

@test "a reference to a renamed file fails, and names the file and the line" {
  # Arrange
  commit_files 'rules/agents.md' 'The rules.' 'README.md' $'# Notes\n\nSee rules/agents.md.'
  git mv -- rules/agents.md rules/environment.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_REFERENCES)" ]]
  [[ "${output}" == 'README.md:3: names rules/agents.md, which this commit renames to rules/environment.md' ]]
}

@test "a reference to a deleted file fails" {
  # Arrange
  commit_files 'docs/old.md' 'Old text.' 'README.md' 'Read old.md first.'
  git rm -q -- docs/old.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_REFERENCES)" ]]
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
  [[ "${status}" -eq 0 ]]
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
  [[ "${status}" -eq "$(exit_code CC_ERR_REFERENCES)" ]]
  [[ "${output}" == 'README.md:1: names sub/README.md, which this commit deletes' ]]
}

@test "a longer name that holds the old one is no reference" {
  # Arrange
  commit_files 'old.md' 'Old.' 'README.md' 'See my-old.md and old.mdx.'
  git rm -q -- old.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "CHANGELOG.md may name the old path" {
  # Arrange
  commit_files 'old.md' 'Old.' 'CHANGELOG.md' 'Renamed old.md to new.md.'
  git mv -- old.md new.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "--exclude leaves a file out of the search" {
  # Arrange
  commit_files 'old.md' 'Old.' 'docs/history.md' 'Once there was old.md.'
  git rm -q -- old.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references --exclude 'docs/*.md'

  # Assert
  [[ "${status}" -eq 0 ]]
}

@test "--exclude without a glob ends with CC_ERR_USAGE" {
  # Act
  run --separate-stderr "${COMMIT_CHECKS}" references --exclude

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_USAGE)" ]]
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
  [[ "${status}" -eq "$(exit_code CC_ERR_TEMPORARY)" ]]
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
  [[ "${status}" -eq 0 ]]
}

@test "untracked lists the files that the commit leaves out, and passes" {
  # Arrange
  commit_files 'README.md' 'Readme.'
  printf 'draft\n' >draft.md

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" untracked

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == 'draft.md' ]]
}

@test "untracked leaves out the files that .gitignore names" {
  # Arrange
  commit_files '.gitignore' '*.log'
  printf 'noise\n' >build.log

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" untracked

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

# endregion Temporary and untracked files

# region Command line

@test "an unknown command ends with CC_ERR_USAGE" {
  # Act
  run --separate-stderr "${COMMIT_CHECKS}" lint

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_USAGE)" ]]
  [[ "${stderr}" == *'unknown command: lint'* ]]
}

@test "outside a repository, a check ends with CC_ERR_GIT" {
  # Arrange
  cd -- "${BATS_TEST_TMPDIR}" || return
  rm -rf -- "${REPOSITORY}"

  # Act
  run --separate-stderr "${COMMIT_CHECKS}" untracked

  # Assert
  [[ "${status}" -eq "$(exit_code CC_ERR_GIT)" ]]
  [[ "${stderr}" == *'run commit-checks inside a git repository'* ]]
}

@test "every exit code stands in the card, the help and the README" {
  # Arrange
  local name value help_text
  local -a violations=()
  help_text="$("${COMMIT_CHECKS}" --help)"

  # Act
  while IFS=' ' read -r name value; do
    if ! grep -qE "^  ${value} ${name}[,.]$" "${COMMIT_CHECKS}"; then
      violations+=("${name}: missing from the card")
    fi
    if [[ "${help_text}" != *"${value}  ${name}:"* ]]; then
      violations+=("${name}: missing from --help")
    fi
    if ! grep -qE "^\| +\`${value}\` +\| +\`${name}\` +\|" "${BATS_TEST_DIRNAME}/../README.md"; then
      violations+=("${name}: missing from the table of README.md")
    fi
  done < <(sed -n 's/^\(CC_ERR_[A-Z_]*\): Final = \([0-9]*\)$/\1 \2/p' "${COMMIT_CHECKS}")

  # Assert
  if ((${#violations[@]} > 0)); then
    printf '%s\n' "${violations[@]}" >&2
    return 1
  fi
}

# endregion Command line

### End
