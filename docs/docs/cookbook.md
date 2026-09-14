---
icon: lucide/cooking-pot
---

# Cookbook

## Running now as a pre-commit hook

```bash
echo "#! /usr/bin/env nix
#! nix shell git+https://codeberg.org/now-runner/now#now --command /bin/sh
now run format" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```
