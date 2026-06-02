💡 Never use `git reset --hard` — destroys uncommitted work

`git reset --hard HEAD` discards ALL local changes, including experiment results,
manual edits, and generated artifacts. It's irreversible and too aggressive.

Safe alternatives:
- `git stash push -m "message"` — saves work, leaves clean state
- `git merge --abort` — clears stale merge state from interrupted operations
- `git checkout HEAD -- path/...` — discards ONLY specific files/directories
- `git clean -fd -- path/...` — removes ONLY untracked files in specific dirs
- `git stash pop` — restores saved work after pull

Use case: pipeline scripts that need to clear auto-evolved files before pulling.
Stash → merge-abort → checkout HEAD on specific dirs → pull → stash pop.
