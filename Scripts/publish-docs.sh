#!/bin/bash
#
# publish-docs.sh — regenerate the DocC site and publish it to the gh-pages
# branch, which GitHub Pages serves at https://<owner>.github.io/<repo>/.
#
# The documentation is built from the working tree, not from HEAD, so commit
# your changes first if you want the published site to match a commit.
#
# Hosted CI cannot run this: building the framework needs the Ultraleap SDK
# installed locally. Run it from a machine that can build the project.
#
# Usage:
#   Scripts/publish-docs.sh [--dry-run] [--output <dir>] [--base-path <path>]
#
#   --dry-run      Build and transform, but do not touch git or push.
#   --output DIR   Write the static site to DIR instead of a temporary
#                  directory. Implies nothing about publishing.
#   --base-path P  Hosting base path. Defaults to the repository name, which
#                  is what a project Pages site is served under.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/LeapSwift.xcodeproj"
SCHEME="LeapSwift"
BRANCH="gh-pages"

DRY_RUN=false
OUTPUT_DIR=""
BASE_PATH=""

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
note() { printf '==> %s\n' "$1"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true; shift ;;
        --output)    OUTPUT_DIR="${2:-}"; [[ -n "$OUTPUT_DIR" ]] || die "--output needs a directory"; shift 2 ;;
        --base-path) BASE_PATH="${2:-}"; [[ -n "$BASE_PATH" ]] || die "--base-path needs a value"; shift 2 ;;
        # Print the header comment, stopping at the first line that is not one,
        # so the help text cannot drift out of sync with the block above.
        -h|--help)   awk 'NR>2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"; exit 0 ;;
        *)           die "unknown argument: $1" ;;
    esac
done

# The base path must match the URL the site is served under, or every asset
# and link 404s.
if [[ -z "$BASE_PATH" ]]; then
    origin_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    [[ -n "$origin_url" ]] || die "no origin remote; pass --base-path explicitly"
    BASE_PATH="$(basename "${origin_url%.git}")"
fi

command -v xcodebuild >/dev/null || die "xcodebuild not found"
[[ -d "$PROJECT" ]] || die "cannot find $PROJECT"

WORK_DIR="$(mktemp -d)"
WORKTREE=""
cleanup() {
    [[ -n "$WORKTREE" ]] && git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    SITE_DIR="$(cd "$OUTPUT_DIR" && pwd)"
    rm -rf "${SITE_DIR:?}/"*
else
    SITE_DIR="$WORK_DIR/site"
fi

# ---- Build ----------------------------------------------------------------

note "Building documentation (this needs the Ultraleap SDK installed)"
xcodebuild docbuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    > "$WORK_DIR/docbuild.log" 2>&1 \
    || { tail -30 "$WORK_DIR/docbuild.log" >&2; die "docbuild failed; full log at $WORK_DIR/docbuild.log"; }

# Surface DocC's own link warnings — the build still succeeds with them, and
# they are the usual reason a symbol link silently renders as plain text.
if grep -E '\.md:[0-9]+:[0-9]+: warning:' "$WORK_DIR/docbuild.log" >/dev/null; then
    printf 'DocC warnings:\n' >&2
    grep -E '\.md:[0-9]+:[0-9]+: warning:' "$WORK_DIR/docbuild.log" | sort -u >&2
fi

ARCHIVE="$(find "$WORK_DIR/DerivedData" -maxdepth 6 -name '*.doccarchive' | head -1)"
[[ -n "$ARCHIVE" ]] || die "no .doccarchive produced"

# ---- Transform for static hosting -----------------------------------------

note "Transforming for static hosting (base path: /$BASE_PATH/)"
xcrun docc process-archive transform-for-static-hosting "$ARCHIVE" \
    --output-path "$SITE_DIR" \
    --hosting-base-path "$BASE_PATH"

# `transform-for-static-hosting` leaves the root index.html pointing at "/",
# unlike the routed pages, so the site root breaks on a project Pages URL.
# Replace it with a redirect to the documentation entry point.
ENTRY="$(basename "$(find "$SITE_DIR/documentation" -maxdepth 1 -mindepth 1 -type d | head -1)")"
[[ -n "$ENTRY" ]] || die "could not determine the documentation entry point"

cat > "$SITE_DIR/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$SCHEME Documentation</title>
<meta http-equiv="refresh" content="0; url=/$BASE_PATH/documentation/$ENTRY">
<link rel="canonical" href="/$BASE_PATH/documentation/$ENTRY">
</head>
<body>
<p>Redirecting to the <a href="/$BASE_PATH/documentation/$ENTRY">$SCHEME documentation</a>.</p>
</body>
</html>
HTML

# Tell Pages to serve the tree as-is rather than running it through Jekyll.
touch "$SITE_DIR/.nojekyll"

note "Built $(find "$SITE_DIR" -type f | wc -l | tr -d ' ') files into $SITE_DIR"

if [[ "$DRY_RUN" == true ]]; then
    note "Dry run: not publishing. Serve it locally with:"
    printf '    cd %s && python3 -m http.server 8000\n' "$SITE_DIR"
    printf '    open http://localhost:8000/documentation/%s/\n' "$ENTRY"
    # Keep the output when the caller asked for a specific directory.
    [[ -n "$OUTPUT_DIR" ]] && trap - EXIT && rm -rf "$WORK_DIR"
    exit 0
fi

# ---- Publish ---------------------------------------------------------------

SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
DIRTY=""
git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet || DIRTY=" (working tree had uncommitted changes)"

WORKTREE="$WORK_DIR/worktree"
note "Preparing the $BRANCH worktree"

if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" fetch --quiet origin "$BRANCH"
    git -C "$REPO_ROOT" worktree add --quiet "$WORKTREE" -B "$BRANCH" "origin/$BRANCH"
else
    note "No remote $BRANCH yet; creating it"
    git -C "$REPO_ROOT" worktree add --quiet --detach "$WORKTREE"
    git -C "$WORKTREE" checkout --quiet --orphan "$BRANCH"
    git -C "$WORKTREE" rm -rq --cached . 2>/dev/null || true
fi

# Replace the branch contents wholesale so deleted pages do not linger.
find "$WORKTREE" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -R "$SITE_DIR/." "$WORKTREE/"

git -C "$WORKTREE" add -A
# Note that this rarely short-circuits. DocC serializes its JSON with the
# per-process dictionary ordering, so two builds of identical sources differ
# by key order throughout, and every run therefore produces a commit. The
# check is here for the case where nothing was rebuilt at all.
if git -C "$WORKTREE" diff --cached --quiet; then
    note "Documentation is unchanged; nothing to publish"
    exit 0
fi

git -C "$WORKTREE" commit --quiet -m "Update DocC documentation from $SOURCE_COMMIT$DIRTY"
note "Pushing $BRANCH"
git -C "$WORKTREE" push --quiet origin "$BRANCH"

OWNER_REPO="$(git -C "$REPO_ROOT" remote get-url origin | sed -E 's|.*[:/]([^/]+/[^/]+)(\.git)?$|\1|; s|\.git$||')"
note "Published. GitHub Pages will rebuild shortly:"
printf '    https://%s.github.io/%s/\n' "${OWNER_REPO%%/*}" "$BASE_PATH"
