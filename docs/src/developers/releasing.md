# Release and package-registration runbook

PowerImpedance is developed on the private KU Leuven GitLab repository.
GitLab contains the development source. GitHub is the public publication repository used by
Julia's General registry. Make release changes on GitLab, not on GitHub.

## Release flow

The release signal is a complete line in the message of the final commit pushed
to GitLab's default branch, `main`:

```text
@JuliaRegistrator register
```

The automation performs this sequence:

```text
GitLab main commit containing the marker
    -> GitLab tests and public-documentation build
    -> fast-forward GitHub main to that exact tested commit, without tags
    -> GitHub Actions posts the real Registrator comment on that commit
    -> General registry pull request
    -> General accepts the version
    -> TagBot creates vX.Y.Z and the GitHub Release
    -> GitHub Release CI validates the tag and deploys stable documentation
```

A commit message alone does not invoke JuliaRegistrator. Our GitLab pipeline
recognizes the marker, publishes the commit, and the tracked GitHub registration
workflow converts that signal into a commit comment that Registrator receives.

Do not create a version tag to start a release. TagBot owns version tags after
registration. Ordinary GitLab commits without the marker remain private until a
later marked commit publishes their history. Merge-request pipelines, scheduled
pipelines, and GitLab tag pushes do not start automatic publication.

## Operator checklist

- [ ] The intended source changes are on GitLab.
- [ ] `Project.toml`, `CHANGELOG.md`, and `CITATION.cff` describe the version.
- [ ] For a new version, that version is not already registered in General.
- [ ] The final commit pushed to GitLab `main` contains the standalone marker.
- [ ] Its GitLab publication preflight and publication job pass.
- [ ] GitHub's **Julia registration** workflow submits that exact commit.
- [ ] The linked General registration pull request passes its checks and merges.
- [ ] TagBot creates the version tag and GitHub Release.
- [ ] **Release CI** passes and stable documentation is deployed.
- [ ] A clean Julia environment installs and loads the intended version.

For corrections to a pending registration, keep the same version. Only a version
already merged into General requires a new version number.

## One-time administrator setup

Ordinary operators should not have to change this configuration.

### GitLab

The default branch must be protected. Configure these protected CI/CD variables:

- `GITHUB_DEPLOY_KEY`: file-type variable containing the private SSH deploy key
  with write access to `Electa-Git/PowerImpedance.jl`.
- `GITHUB_KNOWN_HOSTS`: file-type variable containing the trusted GitHub SSH
  host key.
- `CODECOV_TOKEN`: token for the public GitHub Codecov project.

Protect the `github-force-reconcile` environment and grant deployment permission
only to maintainers authorized to rewrite GitHub `main` in exceptional recovery.

Do not set `POWERIMPEDANCE_PUBLISH` manually. The pipeline derives it from the
push source, branch, and commit-message marker.

### GitHub

The public repository needs:

- the public half of GitLab's SSH deploy key, with write access;
- the [JuliaRegistrator App](https://github.com/JuliaRegistries/Registrator.jl)
  installed for this repository;
- GitHub Actions enabled, including permission for the registration workflow's
  `contents: write`;
- the existing `DOCUMENTER_KEY` Actions secret: a base64-encoded private SSH
  deploy key with write access to this repository;
- GitHub Pages configured to serve the `gh-pages` branch at its root.

No additional GitHub personal access token is required. The registration
workflow uses its automatic `GITHUB_TOKEN` to create the commit comment.
Registrator accepts comments from `github-actions[bot]`.

TagBot uses `DOCUMENTER_KEY` to push tags so those pushes can start **Release CI**.
Documenter uses the same secret to deploy stable documentation.

## 1. Prepare a candidate on GitLab

For a new registered version, prepare a merge request that:

1. sets `version = "X.Y.Z"` in `Project.toml`;
2. puts the release notes in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`;
3. sets the corresponding version and date in `CITATION.cff`;
4. includes the intended source, compatibility, tests, and documentation changes.

The registration workflow reads that version's changelog section and submits it
as release notes. Empty or missing notes cause the workflow to fail before
posting the request.

For a pending version that needs correction, fix the source or metadata on
GitLab but keep its version number. Registrator can amend the existing General
pull request for that version.

Check the version against
[General](https://github.com/JuliaRegistries/General/tree/master/P/PowerImpedance).
Before initial registration that directory may not exist. After a version is
accepted into General, its registered source is immutable.

## 2. Put the signal in the final GitLab main commit

The marker must be a complete line with exactly this spelling and no indentation:

```text
@JuliaRegistrator register
```

For a release merge request, edit the final merge or squash commit message to
include the marker:

```text
chore(release): prepare PowerImpedance 0.3.2

@JuliaRegistrator register
```

A marker in an earlier branch commit is not sufficient if the final
merge or squash commit has a different message. Review the actual final message
in GitLab before merging. Do not include `[skip ci]` or push with CI skipping.

If the intended source is already on GitLab `main`, an authorized maintainer can
make an empty trigger commit from a clean, up-to-date checkout:

```bash
git switch main
git pull --ff-only origin main
test -z "$(git status --porcelain)" || {
    echo 'Stop: working tree or index is not clean.'
    exit 1
}
git commit --allow-empty \
    -m 'chore(release): request Julia registration' \
    -m '@JuliaRegistrator register'
git push origin HEAD:main
```

The working tree and index must be clean before the commit; otherwise unrelated
staged changes could become part of the candidate. Follow the merge-request
route if branch protection does not permit direct pushes.

Record the exact candidate after pushing:

```bash
candidate_sha="$(git rev-parse HEAD)"
printf 'Registration candidate: %s\n' "$candidate_sha"
git log -1 --format=full "$candidate_sha"
```

For a GitLab web merge, copy the resulting `main` commit SHA from the web
interface instead. Do not run `git tag` or push a version tag.

## 3. Check the GitLab pipeline

Open **GitLab > Build > Pipelines** and select the `main` push pipeline for the
recorded candidate. It automatically runs:

1. core tests with coverage, extension tests, and plotting tests;
2. `docs_check`, building documentation with public GitHub source links;
3. `github_release_preflight`, checking authentication, package version, and
   GitLab/GitHub ancestry;
4. `github_release_publish`, fast-forwarding GitHub `main` to the tested pipeline
   SHA; it does not push tags;
5. `github_release_coverage`, uploading that candidate's coverage independently.

The existing `pages` job continues to build private development documentation
on GitLab. Stable public documentation waits until TagBot creates the accepted
version's tag.

Normal publication never force-pushes. It repeats the ancestry checks immediately
before pushing. If GitLab `main` has advanced, it still publishes only the tested
candidate, not the newer branch tip. If GitHub has already advanced beyond that
candidate or diverged, publication stops.

A transient failure before publication can be retried on the same candidate
pipeline. If GitHub already has the exact commit, publication leaves its refs unchanged.
A new registration attempt requires the recovery procedure below because
repeating publication does not produce a GitHub push event.

If coverage alone fails after publication, retry only coverage. Coverage is not
the registration trigger, and a coverage upload failure does not undo a request
already submitted by GitHub automation.

## 4. Verify the automatic registration request

Open **GitHub > Actions > Julia registration** for the candidate. The workflow
posts this comment on the exact SHA from the push, using that commit's changelog:

```text
@JuliaRegistrator register

Release notes:

The notes for this version from CHANGELOG.md.
```

Check the workflow log for the comment URL and the Registrator reply for the
General pull-request link. Do not post another manual comment just because
Registrator has not answered yet.

To inspect public `main`:

```bash
git ls-remote https://github.com/Electa-Git/PowerImpedance.jl.git refs/heads/main
```

Immediately after publication it should report the candidate SHA. A later
publication can move `main` forward; the registration comment remains bound to
its exact candidate.

For an unregistered version, absence of `vX.Y.Z` is expected at this stage.

## 5. Follow the General pull request

Read failed checks and maintainer feedback. General validates registry metadata,
compatibility constraints, and installation/loading in a clean environment.

Waiting periods and AutoMerge policy are defined in the
[General README](https://github.com/JuliaRegistries/General/blob/master/README.md).
Passing checks do not necessarily mean the pull request has merged.

Avoid unnecessary comments on the General pull request: comments can block
AutoMerge. Follow the registry's current instructions when communication is
actually required.

### A pending registration needs source or metadata fixes

1. Make the fixes on GitLab.
2. Keep the same package name, repository URL, and version number.
3. Put the standalone marker in the final corrected `main` commit message.
4. Let the GitLab pipeline publish and submit that new candidate.
5. Verify that Registrator updated the existing General pull request.

Do not bump the version merely to fix a pending submission; that would create a
different registration pull request. Do not make corrections on GitHub.

### Registration automation failed before submitting the request

Correct any workflow, permissions, App installation, or changelog problem.
Then make a new marked commit on GitLab `main`; an empty trigger commit is
sufficient for a transient failure once configuration is corrected. The new
push automatically starts publication and registration again.

Retrying an unchanged GitLab publication job after a successful push is not
enough to restart GitHub Actions, because Git has no new branch update to send.

### The version is already merged into General

Do not resubmit changed package source under that version. Prepare a new version
on GitLab and use the same marker-driven procedure.

## 6. Verify TagBot and stable documentation

After General accepts the version, TagBot creates `vX.Y.Z` for the accepted
source and publishes the GitHub Release with the submitted notes.

Check **GitHub > Actions > TagBot**, **GitHub > Releases**, and **Release CI**.
The tag must identify the registered source; it need not point to a later `main`
tip. Release CI validates its package version and that its commit belongs to
GitHub `main` history, then builds and deploys stable documentation from the tag.

Do not create a competing version tag on GitLab or GitHub. A GitLab copy of the
tag is not required for registration or subsequent publication.

If TagBot or documentation alone fails, registration may already be complete.
Inspect that workflow and repair the specific problem. Do not retrigger
Registrator to repair release metadata or documentation. Administrative TagBot
recovery can use its existing workflow-dispatch control without changing the
registered tag.

## 7. Verify installation

After registry/package-server propagation, check the intended version in a
temporary Julia environment. Substitute the actual accepted version:

```bash
julia --startup-file=no -e '
    using Pkg
    Pkg.activate(; temp = true)
    Pkg.Registry.update()
    Pkg.add(PackageSpec(name = "PowerImpedance", version = "0.3.2"))
    using PowerImpedance
    Pkg.status(["PowerImpedance"])
'
```

The package must resolve from General, not from a local checkout or a Git URL.

## Troubleshooting

### The marked commit did not publish

Check the final pushed commit message, not the merge-request title or an earlier
commit. Publication requires a push pipeline on the default branch with a
standalone marker. A manually created or scheduled pipeline is not a release
signal. Check that CI was not skipped and that all required tests/docs passed.

### An old GitLab tag pipeline still offers publication jobs

Pipelines use the configuration from their own commit. Historical tag pipelines
can still contain the old tag-publishing job. Do not retry those jobs
or create tags on historical commits to start a release. Use a marked commit on
GitLab main containing the current workflow instead.

### GitHub main has diverged

Normal publication stops without overwriting GitHub. Review the differences.
An authorized maintainer can run the protected `github_force_reconcile` job from
the latest GitLab `main` pipeline. It archives the former GitHub `main` under an
`archive/github-main-before-reconcile-*` tag before reconciliation.

This is exceptional recovery. Once reconciliation is reviewed, use a new marked
GitLab commit to return to the tested publication/registration sequence.

### A version tag already exists before acceptance

Do not repeatedly move it. Determine whether General already accepted that
version. If registration is still pending and a premature tag is blocking it,
an authorized administrator must remove the premature public tag, after
checking the exact repository and target, then leave tag creation to TagBot.
Deleting a GitLab tag does not delete a GitHub tag.

Do not delete or move a correctly registered version tag.

### No Registrator response

Check the **Julia registration** workflow log and its comment URL. Confirm that
the App is installed for the public repository and that Actions has
`contents: write`. If a real fix or retry is required, trigger it from GitLab
with a new marked candidate.

## Release configuration

- `.gitlab-ci.yml`: marker recognition, tests, docs validation, preflight,
  publication, coverage, and private development Pages.
- `.gitlab/publish_github.sh`: exact-SHA, fast-forward-only publication with
  version-tag pushing disabled.
- `.github/workflows/register.yml`: automatic commit comment and release notes.
- `.github/workflows/TagBot.yml`: post-registration version tag and Release.
- `.github/workflows/release-ci.yml`: tag validation and stable documentation.
- `docs/deploy_github.jl`: Documenter deployment configuration.
- `.gitlab/force_reconcile_github.sh`: protected exceptional reconciliation.

Official references:
[Registrator](https://github.com/JuliaRegistries/Registrator.jl),
[General policy](https://github.com/JuliaRegistries/General/blob/master/README.md),
[TagBot](https://github.com/JuliaRegistries/TagBot), and
[Documenter hosting](https://documenter.juliadocs.org/stable/man/hosting/).
