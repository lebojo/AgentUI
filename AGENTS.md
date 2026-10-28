# Agent instructions

## Releases

Never create a new version without asking the user first and getting an explicit yes. This covers:

- creating or pushing a Git tag (any tag push triggers `.github/workflows/release.yml`, which builds, signs, notarizes and publishes a GitHub release);
- creating, editing or deleting a GitHub release;
- changing `MARKETING_VERSION` or the version shown on the site.

Approval for one version does not carry over to the next one. When the user approves, the release is made with:

```sh
git tag -a <version> -m "AgentUI <version>"
git push origin <version>
```
