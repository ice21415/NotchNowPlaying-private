# NotchNowPlaying CI setup

## Charging flow builds (0.1.109)

The source repository is `ice21415/NotchNowPlaying-private` (public despite its
historical name). The charging flow branch is `codex/charging-flow-20261002`.
Its `build-charging.yml` workflow uses the standard `macos-26` runner with
Apple Clang and builds both `normal` and `aod` packages. The `aod` variant
preserves the previous Phase 7 experimental build flags. Download the package
artifact matching the desired variant; both use the version recorded in `control`.

The workflow checks Apple compiler identity, arm64e architecture, package
version, charging settings, injection filters, and incompatible ABI warnings.
It uploads artifacts without publishing to the separate package repository.
No `PUBLIC_REPO_TOKEN` is required for this workflow.

Public repositories using standard hosted runners do not consume private
repository build minutes. Concurrency and artifact-storage limits still apply.
Compiler success does not replace device verification of private iOS APIs.

## Legacy publishing setup

The instructions below describe the older publishing workflow.

Source repository:

```text
ice21415/NotchNowPlaying-private
```

Public package repository:

```text
ice21415/NotchNowPlaying
```

In the private repository, add a GitHub Actions secret named:

```text
PUBLIC_REPO_TOKEN
```

The token needs permission to push to `ice21415/NotchNowPlaying`.

Normal pushes currently build the safe-boot test variant. Build logs and the `.deb` are retained as Actions artifacts. The formal MediaRemote build will be enabled only after the safe-boot CI path is confirmed.
