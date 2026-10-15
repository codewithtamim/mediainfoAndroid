#!/bin/sh
# Applies patches/*.patch onto git submodules. Idempotent: skips already-applied patches.
# Patches are stored submodule-relative (a/Source/...), applied with `git apply` inside each submodule.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

apply_patch() {
  submodule_dir="$1"
  patch_file="$2"
  name="$(basename "$patch_file")"
  target="$ROOT/$submodule_dir"

  if [ ! -d "$target/.git" ] && [ ! -f "$target/.git" ]; then
    echo "error: submodule '$submodule_dir' is not checked out (missing $target/.git)."
    echo "hint: run 'git submodule update --init --recursive' first."
    exit 1
  fi

  # Already applied? `git apply --reverse --check` succeeds only when the patch is fully applied.
  if git -C "$target" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "skip (already applied): $name -> $submodule_dir"
    return 0
  fi

  if ! git -C "$target" apply --check "$patch_file"; then
    echo "error: patch '$name' does not apply cleanly to '$submodule_dir'."
    echo "hint: upstream branch moved; refresh the patch against the new submodule HEAD."
    exit 1
  fi

  git -C "$target" apply "$patch_file"
  echo "applied: $name -> $submodule_dir"
}

applied_any=0
for patch in "$ROOT"/patches/MediaInfoLib-*.patch; do
  # Glob with no match expands literally; skip in that case.
  [ -e "$patch" ] || continue
  apply_patch "dependencies/MediaInfoLib" "$patch"
  applied_any=1
done

for patch in "$ROOT"/patches/ZenLib-*.patch; do
  [ -e "$patch" ] || continue
  apply_patch "dependencies/ZenLib" "$patch"
  applied_any=1
done

if [ "$applied_any" -eq 0 ]; then
  echo "no patches found under patches/ (nothing to do)"
fi
