#!/bin/sh
set -eu

test "${POWERIMPEDANCE_PUBLISH:-false}" = "true" || {
    echo "REFUSED: not a marked publication pipeline"
    exit 1
}
test "${CI_COMMIT_BRANCH:-}" = "$CI_DEFAULT_BRANCH" &&
    test -z "${CI_COMMIT_TAG:-}" || {
    echo "REFUSED: publication must originate from the GitLab default branch"
    exit 1
}
test "$(git rev-parse HEAD)" = "$CI_COMMIT_SHA" || {
    echo "REFUSED: checkout does not match the tested candidate"
    exit 1
}

git fetch --no-tags origin \
    "+refs/heads/${CI_DEFAULT_BRANCH}:refs/remotes/origin/${CI_DEFAULT_BRANCH}"
git fetch --no-tags github \
    "+refs/heads/main:refs/remotes/github/main"

git merge-base --is-ancestor \
    "$CI_COMMIT_SHA" "refs/remotes/origin/${CI_DEFAULT_BRANCH}" || {
    echo "REFUSED: candidate commit is not on authoritative GitLab main"
    exit 1
}
git merge-base --is-ancestor refs/remotes/github/main "$CI_COMMIT_SHA" || {
    echo "REFUSED: GitHub main is not an ancestor of this candidate"
    echo "Review the protected github_force_reconcile job; no force-push was attempted."
    exit 1
}

# Never publish tags, including locally present tags or push.followTags tags.
# Publish the tested pipeline SHA, not a newer, untested origin/main tip.
git -c push.followTags=false push github "${CI_COMMIT_SHA}:refs/heads/main"
echo "Published candidate $CI_COMMIT_SHA to GitHub main; no version tag was created."
