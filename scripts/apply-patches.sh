#!/bin/sh
# Ensures the MediaInfoLib/ZenLib sources exist and applies patches/*.patch.
# Idempotent: valid checkouts are left alone, already-applied patches skipped.
#
# Why the ensure-step exists: `git submodule update` cannot run in some
# environments (notably JitPack, which checks out with a detached GIT_DIR and
# no writable modules dir). This script therefore repairs missing or broken
# checkouts itself via an explicit clone + checkout of the pinned revision,
# without depending on any superproject git state.
#
# Pinned revisions below must be kept in sync with the submodule gitlinks;
# bump them together. Patches are stored submodule-relative (a/Source/...)
# and applied with `git apply` inside each submodule.
set -eu

# JitPack (and some CI setups) export GIT_DIR / GIT_WORK_TREE pointing at their
# own git metadata dir. That breaks every `git -C <submodule>` invocation
# ("Not a git repository: .../.git/modules/..."), so clear them here. This also
# covers the Gradle applyPatches task, which inherits the ambient environment.
unset GIT_DIR GIT_WORK_TREE GIT_NAMESPACE GIT_INDEX_FILE GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MEDIAINFOLIB_URL="https://github.com/MediaArea/MediaInfoLib.git"
MEDIAINFOLIB_REV="153ad67a62172534b401e9d9a5752dc759fff77b"
ZENLIB_URL="https://github.com/MediaArea/ZenLib.git"
ZENLIB_REV="07c0ef8a121e025fbb27388c28291447c379bf35"

ensure_content() {
  name="$1"
  url="$2"
  rev="$3"
  target="$ROOT/dependencies/$name"

  # NOTE: the `.git` existence gate must come first. Without it, `git -C`
  # walks up and discovers the *parent* repo, falsely reporting success when
  # the submodule checkout is actually missing or broken.
  if { [ -d "$target/.git" ] || [ -f "$target/.git" ]; } \
      && git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "sources present: $name"
    return 0
  fi

  echo "sources missing or broken: $name -- cloning $url@$rev"
  rm -rf "$target"
  mkdir -p "$ROOT/dependencies"
  if git init -q "$target" \
      && git -C "$target" remote add origin "$url" \
      && git -C "$target" fetch --depth 1 origin "$rev" \
      && git -C "$target" checkout -q FETCH_HEAD; then
    echo "cloned (shallow): $name"
  else
    echo "shallow fetch failed, falling back to full clone: $name"
    rm -rf "$target"
    git clone "$url" "$target"
    git -C "$target" checkout -q "$rev"
    echo "cloned (full): $name"
  fi
}

apply_patch() {
  submodule_dir="$1"
  patch_file="$2"
  name="$(basename "$patch_file")"
  target="$ROOT/$submodule_dir"

  # Already applied? `git apply --reverse --check` succeeds only when the patch is fully applied.
  if git -C "$target" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "skip (already applied): $name -> $submodule_dir"
    return 0
  fi

  if ! git -C "$target" apply --check "$patch_file"; then
    echo "error: patch '$name' does not apply cleanly to '$submodule_dir'."
    echo "hint: upstream moved past the pinned revision; bump the pinned REV and refresh the patch."
    exit 1
  fi

  git -C "$target" apply "$patch_file"
  echo "applied: $name -> $submodule_dir"
}

ensure_content "MediaInfoLib" "$MEDIAINFOLIB_URL" "$MEDIAINFOLIB_REV"
ensure_content "ZenLib" "$ZENLIB_URL" "$ZENLIB_REV"

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
