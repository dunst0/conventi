#!/usr/bin/env sh

##
# Copyright (c) 2023 Rick Barenthin
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
#  1. Redistribution of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
#
#  2. Redistribution in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#
#  3. Neither the name of the copyright holder nor the names of its contributors
#     may be used to endorse or promote products derived from this software without
#     specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.
#
# YOU ACKNOWLEDGE THAT THIS SOFTWARE IS NOT DESIGNED, LICENSED OR INTENDED FOR USE
# IN THE DESIGN, CONSTRUCTION, OPERATION OR MAINTENANCE OF ANY MILITARY FACILITY.
#
# YOU ACKNOWLEDGE THAT THIS SOFTWARE IS NOT DESIGNED, LICENSED OR INTENDED FOR USE
# IN THE DESIGN, CONSTRUCTION, OPERATION OR MAINTENANCE OF ANY NUCLEAR FACILITY.
##

config_file=.version.json
changelog_file=CHANGELOG.md
changelog_header="# Changelog

All notable changes to this project will be documented in this file. See [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for commit guidelines.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

----
"

reverse() {
  if which tac >/dev/null 2>&1; then
    tac
  else
    tail -r
  fi
}

generate_config() {
  url="$1"
  format="default"

  if echo "$url" | grep -q  "://bitbucket.org"; then
    format="bitbucket"
  fi

  jq --null-input \
    --arg version "0.0.0" \
    --arg sha "" \
    --arg url "$url" \
    --arg format "$format" \
    '{ "version": $version, "sha": $sha, "url": $url, "format": $format }' >$config_file
}

update_config() {
  # store in a var as reading and writing in one go to one file is not good
  config=$(jq '.sha |= $sha | .version |= $version' --arg sha "$1" --arg version "$2" $config_file)
  echo "$config" >$config_file
}

get_config_version() {
  jq '.version' <$config_file | tr -d '"'
}

get_config_sha() {
  jq '.sha' <$config_file | tr -d '"'
}

get_config_url() {
  jq '.url' <$config_file | tr -d '"'
}

get_config_format() {
  jq '.format' <$config_file | tr -d '"'
}

##
# PARAM 1: SemVer formatted version
split_version_string() {
  version_number=$(echo "$1" | cut -d'-' -f1 | cut -d'+' -f1)
  pre_release=$(echo "$1" | cut -d'-' -f2 | cut -d'+' -f1)
  build=$(echo "$1" | cut -d'-' -f2 | cut -d'+' -f2)
  if [ "$pre_release" = "$1" ]; then
    pre_release=""
  fi
  if [ "$build" = "$1" ] || [ "$build" = "$pre_release" ]; then
    build=""
  fi

  major=$(echo "$version_number" | cut -d'.' -f1)
  minor=$(echo "$version_number" | cut -d'.' -f2)
  patch=$(echo "$version_number" | cut -d'.' -f3)

  pre_release_name=$(echo "$pre_release" | cut -d'.' -f1)
  pre_release_id=$(echo "$pre_release" | cut -d'.' -f2)

  echo "${major:-0} ${minor:-0} ${patch:-0} ${pre_release_name} ${pre_release_id} $build"
}

##
# PARAM 1: SemVer formatted version
# PARAM 2: number that identifies the impact of change to determine the next version
# PARAM 3: if set to "build", then the short git hash is added
# PARAM 4: pre-release type
calculate_version() {
  version_string=$(split_version_string "$1")
  major=$(echo "$version_string" | cut -d' ' -f1)
  minor=$(echo "$version_string" | cut -d' ' -f2)
  patch=$(echo "$version_string" | cut -d' ' -f3)
  pre_release_name=$(echo "$version_string" | cut -d' ' -f4)
  pre_release_id=$(echo "$version_string" | cut -d' ' -f5)
  build=$(echo "$version_string" | cut -d' ' -f6)

  if [ "$2" -ge 100 ]; then
    major=$((major + 1))
    minor=0
    patch=0
  elif [ "$2" -ge 10 ]; then
    minor=$((minor + 1))
    patch=0
  elif [ "$2" -ge 1 ]; then
    patch=$((patch + 1))
  fi

  if [ -n "$4" ]; then
    if [ -z "$pre_release_id" ] || [ "$4" != "$pre_release_name" ]; then
      pre_release_id=1
      pre_release_name="$4"
    else
      pre_release_id=$((pre_release_id + 1))
    fi
    pre_release="$pre_release_name.$pre_release_id"
  fi

  if [ "$3" = "build" ]; then
    build="$(git rev-parse --short HEAD)"
  else
    build=""
  fi

  version_number="${major}.${minor}.${patch}"
  if [ -n "$pre_release" ]; then
    pre_release="-$pre_release"
  fi
  if [ -n "$build" ]; then
    build="+$build"
  fi

  echo "${version_number}${pre_release}${build}"
}

get_git_url() {
  url=$(git config --get remote.origin.url)
  if ! echo "$url" | grep -q "^http"; then
    url=$(echo "$url" | cut -d@ -f2 | sed 's/:/\//')
    url="https://${url:-localhost}"
  fi

  echo "$url" | sed 's/\.git$//'
}

get_git_commits() {
  since_hash=$(get_config_sha)
  if [ -n "$since_hash" ]; then
    git rev-list "$since_hash..HEAD"
  else
    git rev-list HEAD
  fi
}

get_git_commit_hash() {
  git rev-parse --short "$1"
}

get_git_first_commit_hash() {
  git rev-list --max-parents=0 --abbrev-commit HEAD
}

get_git_commit_subject() {
  git show -s --format=%s "$1"
}

get_git_commit_body() {
  git show -s --format=%b "$1"
}

get_commit_type() {
  echo "$1" | sed -r -n 's/([a-z]+)(\(?|:?).*/\1/p' | tr '[:upper:]' '[:lower:]'
}

get_commit_scope() {
  echo "$1" | sed -r -n 's/[a-z]+\(([^)]+)\).*/\1/p'
}

get_commit_description() {
  echo "$1" | sed -r -n 's/.*:[ ]+(.*)/\1/p'
}

get_commit_footer() {
  with_colon=$(echo "$1" | sed -n '/^[A-Za-z-]\{1,\}: /,//{p;}')
  with_hash=$(echo "$1" | sed -n '/^[A-Za-z-]\{1,\} #/,//{p;}')
  fallback=$(echo "$1" | reverse | awk '/^$/{exit}1' | reverse)

  if [ -z "$with_colon" ] && [ -z "$with_hash" ]; then
    echo "$fallback"
  elif [ ${#with_colon} -gt ${#with_hash} ]; then
    echo "$with_colon"
  else
    echo "$with_hash"
  fi
}

get_commit_body() {
  pattern=$(get_commit_footer "$1" | head -n 1 | sed -e 's/[]\/$*.^[]/\\&/g')
  if [ -n "$pattern" ]; then
    echo "$1" | sed -e "/$pattern/,\$d"
  else
    echo "$1"
  fi
}

is_breaking_change() {
  if echo "$1" | grep -q '!' || echo "$2" | grep -q 'BREAKING[ -]CHANGE: '; then
    echo 1
  else
    echo 0
  fi
}

get_breaking_change() {
  with_colon=$(echo "$1" | sed -n '/^BREAKING[ -]CHANGE: /,/^[A-Za-z-]\{1,\}: /{ s/BREAKING[ -]CHANGE: \(.*\)/\1/; /^[A-Za-z-]\{1,\}: /!p;}')
  with_hash=$(echo "$1" | sed -n '/^BREAKING[ -]CHANGE: /,/^[A-Za-z-]\{1,\} #/{ s/BREAKING[ -]CHANGE: \(.*\)/\1/; /^[A-Za-z-]\{1,\} #/!p;}')
  if [ -n "$with_colon" ] && ! echo "$with_colon" | grep -q '[A-Za-z-]\{1,\} #'; then
    echo "$with_colon"
  else
    echo "$with_hash"
  fi
}

##
# PARAM 1: commit hash
#
# bitbucket: /commits/$hash
# github: /commit/$hash
# gitea: /commit/$hash
# gitlab: /commit/$hash
format_commit_url() {
  case "$(get_config_format)" in
    bitbucket)
      echo "$(get_config_url)/commits/$1"
      ;;
    *)
      echo "$(get_config_url)/commit/$1"
      ;;
  esac
}

##
# PARAM 1: from commit hash
# PARAM 2: to commit hash
# bitbucket: /compare/$to_hash..$from_hash
# github: /compare/$from_hash...$to_hash
# gitea: /compare/$from_hash...$to_hash
# gitlab: /compare/$from_hash...$to_hash
format_compare_url() {
  case "$(get_config_format)" in
    bitbucket)
      echo "$(get_config_url)/compare/$2..$1"
      ;;
    *)
      echo "$(get_config_url)/compare/$1...$2"
      ;;
  esac
}

format_entry_line() {
  line=""
  if [ -n "$2" ]; then
    line="**$2:** "
  fi
  line="$line$1"

  echo "$line ([$3]($(format_commit_url "$3")))" | sed -e '2,$s/^[ ]*/  /'
}

breaking_change_lines=""
build_lines=""
chore_lines=""
ci_lines=""
doc_lines=""
feature_lines=""
bugfix_lines=""
perf_lines=""
refactor_lines=""
revert_lines=""
style_lines=""
test_lines=""

add_changelog_entry_line() {
  case "$1" in
    build)
      build_lines=$(printf '%s\n* %s\n' "$build_lines" "$2")
      ;;
    chore)
      chore_lines=$(printf '%s\n* %s\n' "$chore_lines" "$2")
      ;;
    ci)
      ci_lines=$(printf '%s\n* %s\n' "$ci_lines" "$2")
      ;;
    docs)
      doc_lines=$(printf '%s\n* %s\n' "$doc_lines" "$2")
      ;;
    feat)
      feature_lines=$(printf '%s\n* %s\n' "$feature_lines" "$2")
      ;;
    fix)
      bugfix_lines=$(printf '%s\n* %s\n' "$bugfix_lines" "$2")
      ;;
    perf)
      perf_lines=$(printf '%s\n* %s\n' "$perf_lines" "$2")
      ;;
    refactor)
      refactor_lines=$(printf '%s\n* %s\n' "$refactor_lines" "$2")
      ;;
    revert)
      revert_lines=$(printf '%s\n* %s\n' "$revert_lines" "$2")
      ;;
    style)
      style_lines=$(printf '%s\n* %s\n' "$style_lines" "$2")
      ;;
    test)
      test_lines=$(printf '%s\n* %s\n' "$test_lines" "$2")
      ;;
  esac
}

format_entry() {
  entry=""
  if [ -n "$breaking_change_lines" ]; then
    entry=$(printf '%s\n\n\n### BREAKING CHANGES 🚨\n%s\n' "$entry" "$breaking_change_lines")
  fi
  if [ -n "$bugfix_lines" ]; then
    entry=$(printf '%s\n\n\n### Bug fixes 🩹\n%s\n' "$entry" "$bugfix_lines")
  fi
  if [ -n "$feature_lines" ]; then
    entry=$(printf '%s\n\n\n### Features 📦\n%s\n' "$entry" "$feature_lines")
  fi
  if [ -n "$revert_lines" ]; then
    entry=$(printf '%s\n\n\n### Reverts 🔙\n%s\n' "$entry" "$revert_lines")
  fi
  if [ -n "$build_lines" ]; then
    entry=$(printf '%s\n\n\n### Build System 🏗\n%s\n' "$entry" "$build_lines")
  fi
  if [ -n "$chore_lines" ]; then
    entry=$(printf '%s\n\n\n### Chores 🧽\n%s\n' "$entry" "$chore_lines")
  fi
  if [ -n "$ci_lines" ]; then
    entry=$(printf '%s\n\n\n### CIs ⚙️\n%s\n' "$entry" "$ci_lines")
  fi
  if [ -n "$doc_lines" ]; then
    entry=$(printf '%s\n\n\n### Docs 📑\n%s\n' "$entry" "$doc_lines")
  fi
  if [ -n "$test_lines" ]; then
    entry=$(printf '%s\n\n\n### Tests 🧪\n%s\n' "$entry" "$test_lines")
  fi
  if [ -n "$style_lines" ]; then
    entry=$(printf '%s\n\n\n### Styles 🖼\n%s\n' "$entry" "$style_lines")
  fi
  if [ -n "$refactor_lines" ]; then
    entry=$(printf '%s\n\n\n### Refactors 🛠\n%s\n' "$entry" "$refactor_lines")
  fi
  if [ -n "$perf_lines" ]; then
    entry=$(printf '%s\n\n\n### Performance 🏎\n%s\n' "$entry" "$perf_lines")
  fi

  if [ -n "$entry" ]; then
    entry=$(printf '## [%s](%s) (%s)%s' "$version" "$(format_compare_url "$from_hash" "$to_hash")" "$(date '+%Y-%m-%d')" "$entry")
  fi
  echo "$entry"
}

generate_changelog_entry() {
  is_major=0
  is_minor=0
  is_patch=0

  version=$(get_config_version)
  from_hash=$(get_config_sha)
  if [ -z "$from_hash" ]; then
    from_hash=$(get_git_first_commit_hash)
  fi
  to_hash=$(get_git_commit_hash HEAD)

  for commit in $(get_git_commits); do
    git_subject=$(get_git_commit_subject "$commit")
    git_body=$(get_git_commit_body "$commit")
    hash=$(get_git_commit_hash "$commit")

    type=$(get_commit_type "$git_subject")
    scope=$(get_commit_scope "$git_subject")
    description=$(get_commit_description "$git_subject")
    body=$(get_commit_body "$git_body")
    footer=$(get_commit_footer "$git_body")
    breaking_change=$(get_breaking_change "$footer")
    is_breaking=$(is_breaking_change "$git_subject" "$footer")
    line=$(format_entry_line "$description" "$scope" "$hash")

    if [ "$is_breaking" -eq 1 ] && [ -z "$breaking_change" ]; then
      if [ -n "$body" ]; then
        breaking_change="$body"
      else
        breaking_change="$description"
      fi
    fi

    if [ "$is_breaking" -eq 1 ]; then
      is_major=1
      breaking_change=$(echo "$breaking_change" | sed -e '2,$s/^[ ]*/  /')
      breaking_change_lines=$(printf '%s\n* %s\n' "$breaking_change_lines" "$breaking_change")
    fi

    case "$type" in
      feat)
        is_minor=1
        ;;

      fix)
        is_patch=1
        ;;
    esac

    add_changelog_entry_line "$type" "$line"
  done

  version_update=$((is_major * 100 + is_minor * 10 + is_patch))
  if [ $version_update -gt 0 ]; then
    version=$(calculate_version "$version" "$version_update")
  else
    # no version change, no need to generate changelog
    return
  fi

  update_config "$to_hash" "$version"

  format_entry
}

new_changelog() {
  echo "$changelog_header" >$changelog_file
}

get_version() {
  calculate_version "$(get_config_version)" 0 "$@"
}

new_changelog_entry() {
  entry=$(generate_changelog_entry)
  if [ -z "$entry" ]; then
    return
  fi

  changelog=$(sed -n '/^----/,//{/^----/!p;}' <$changelog_file)
  if [ -n "$changelog" ]; then
    changelog=$(printf '%s\n%s\n%s' "$changelog_header" "$entry" "$changelog")
  else
    changelog=$(printf '%s\n%s' "$changelog_header" "$entry")
  fi
  echo "$changelog" >$changelog_file
}

init() {
  if [ "$1" = "--help" ]; then
    echo "$(basename "$0") [--help] [init|get_version]"
    exit 0
  elif [ "$1" = "init" ]; then
    echo "Generating a config ... "
    echo "We guessed that the url for git links will be: $(get_git_url)"
    echo "Please change inside the '${config_file}' file if needed!"
    generate_config "$(get_git_url)"
    new_changelog
    exit 0
  fi

  if [ ! -f "$config_file" ]; then
    echo >&2 "ERROR: config file is missing to generate changelog entry"
    exit 1
  fi

  if [ "$1" = "get_version" ]; then
    get_version "$2" "$3"
    exit 0
  fi

  echo "Using existing config to generate changelog entry"
  new_changelog_entry
}

init "$@"