#!/usr/bin/env bash
# Prints the tags of upstream buildah's GitHub releases since MIN_VERSION, oldest first.
# Drafts and pre-releases are skipped.
set -euo pipefail

UPSTREAM="${UPSTREAM:-podman-container-tools/buildah}"
MIN_VERSION="${MIN_VERSION:-v1.26.0}"

# GitHub's releases API sometimes answers 200 with an empty page, so a list is only
# accepted when it contains the latest release.
latest="$(gh api "repos/${UPSTREAM}/releases/latest" --jq .tag_name)"
for attempt in 1 2 3 4 5; do
  tags="$(gh api --paginate "repos/${UPSTREAM}/releases" --jq '.[] | select(.draft or .prerelease | not) | .tag_name')"
  if grep -qxF "${latest}" <<<"${tags}"; then
    break
  fi
  if ((attempt == 5)); then
    echo "releases of ${UPSTREAM} do not include the latest release ${latest}" >&2
    exit 1
  fi
  sleep $((attempt * 5))
done

sort -V <<<"${tags}" |
  while read -r tag; do
    if [[ "$(printf '%s\n' "${MIN_VERSION}" "${tag}" | sort -V | head -1)" == "${MIN_VERSION}" ]]; then
      echo "${tag}"
    fi
  done
