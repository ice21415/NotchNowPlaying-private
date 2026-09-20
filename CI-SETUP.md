# NotchNowPlaying CI setup

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
