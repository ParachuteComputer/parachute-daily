# Development Workflow

## Branching

- **Never push directly to main.** All changes go through PRs.
- Create a feature branch for every change: `feature/*`, `fix/*`, `docs/*`, `chore/*`
- Open a PR with a summary even for self-merge — creates a paper trail
- Squash-merge to keep main clean
- Delete the branch after merge

## PR Process

1. Create a branch: `git checkout -b feature/my-change`
2. Make changes, commit with conventional commits
3. Push: `git push -u origin feature/my-change`
4. Create PR: `gh pr create --title "feat: ..." --body "..."`
5. Review the diff (or have it reviewed)
6. Merge: `gh pr merge <number> --squash --delete-branch`

**Do not** use `git push origin main` or merge without a PR. PRs are the record of what changed and why.

## Before Committing

Run static analysis before every commit:

```bash
flutter analyze
```

If it fails, fix before committing. No exceptions.

## Commit Messages

Follow conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`

Keep the first line under 72 characters. Add a body for non-trivial changes explaining *why*, not *what*.

## Deploying to Device

Don't deploy mid-debug. The workflow is:
1. Make changes
2. Run analyze
3. Commit to branch
4. Build and deploy APK
5. Test on device
6. If broken, fix on the branch — don't iterate APK installs without commits

## PRs

Use `gh pr create` with a summary. Include a test plan. Format:

```
## Summary
- Bullet points of what changed

## Test plan
- [ ] Checklist of things to verify
```
