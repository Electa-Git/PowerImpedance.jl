#!/bin/sh

set -eu

gitlab_remote="${GITLAB_REMOTE_NAME:-origin}"
github_remote="${GITHUB_REMOTE_NAME:-github}"
gitlab_branch="${CI_DEFAULT_BRANCH:?CI_DEFAULT_BRANCH is required}"
github_branch="${GITHUB_DEFAULT_BRANCH:-main}"
pipeline_sha="${CI_COMMIT_SHA:?CI_COMMIT_SHA is required}"
archive_prefix="${GITHUB_ARCHIVE_TAG_PREFIX:-archive/github-main-before-reconcile}"

git fetch --no-tags "$gitlab_remote" \
    "+refs/heads/${gitlab_branch}:refs/remotes/${gitlab_remote}/${gitlab_branch}"

gitlab_sha="$(git rev-parse "refs/remotes/${gitlab_remote}/${gitlab_branch}")"

if [ "$pipeline_sha" != "$gitlab_sha" ]; then
    echo "REFUSED: this pipeline is not for the current ${gitlab_remote}/${gitlab_branch}."
    echo "Start the reconciliation from the latest default-branch pipeline."
    exit 1
fi

github_sha="$(
    git ls-remote --heads "$github_remote" "refs/heads/${github_branch}" |
        awk 'NR == 1 { print $1 }'
)"

if [ -z "$github_sha" ]; then
    git push --atomic "$github_remote" \
        "${gitlab_sha}:refs/heads/${github_branch}"
    echo "Published ${gitlab_sha} as ${github_remote}/${github_branch}."
    exit 0
fi

if [ "$github_sha" = "$gitlab_sha" ]; then
    echo "${github_remote}/${github_branch} already matches ${gitlab_remote}/${gitlab_branch}."
    exit 0
fi

git fetch --no-tags "$github_remote" \
    "+refs/heads/${github_branch}:refs/remotes/${github_remote}/${github_branch}"

short_github_sha="$(printf '%s' "$github_sha" | cut -c1-12)"
archive_tag="${archive_prefix}-${short_github_sha}"
archive_sha="$(
    git ls-remote --refs --tags "$github_remote" "refs/tags/${archive_tag}" |
        awk 'NR == 1 { print $1 }'
)"

if [ -n "$archive_sha" ] && [ "$archive_sha" != "$github_sha" ]; then
    echo "REFUSED: ${archive_tag} exists and points to ${archive_sha}."
    exit 1
fi

git push --atomic \
    --force-with-lease="refs/heads/${github_branch}:${github_sha}" \
    "$github_remote" \
    "${github_sha}:refs/tags/${archive_tag}" \
    "${gitlab_sha}:refs/heads/${github_branch}"

echo "Archived the previous GitHub main as ${archive_tag}."
echo "Reconciled ${github_remote}/${github_branch} to ${gitlab_sha}."
