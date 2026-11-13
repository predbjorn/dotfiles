#!/usr/bin/env bash
# disk-cleanup.sh — reclaim regenerable build caches, without breaking work in progress.
#
#   disk-cleanup.sh              clean (safe targets only)
#   disk-cleanup.sh --dry-run    report what would be deleted, delete nothing
#   disk-cleanup.sh --deep       also clear slow-to-refetch caches (Gradle, ML models etc)
#   disk-cleanup.sh --age N      only delete build output untouched for N hours (default 24)
#   disk-cleanup.sh --progress   also emit "::" progress lines (for DiskCleaner.app)
#
# Everything here is rebuilt or re-downloaded on demand. It never touches repo
# state, simulators, the Trash, symlinked (relocated) data, or anything you
# authored. Build output that was written recently, or that a running build may
# be using, is left alone.
set -u

HACKING="${HACKING:-$HOME/Hacking}"
LOG="$HOME/Library/Logs/disk-cleanup.log"
DRY=0; DEEP=0; PROGRESS=0; AGE_H=24
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) DRY=1 ;;
    --deep)       DEEP=1 ;;
    --age)        shift; AGE_H="${1:?--age needs hours}" ;;
    --progress)   PROGRESS=1 ;;
    -h|--help)    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
AGE_MIN=$(( AGE_H * 60 ))

free_mb() { df -m /System/Volumes/Data | tail -1 | awk '{print $4}'; }
size_mb() { [ -e "$1" ] && du -sm "$1" 2>/dev/null | cut -f1 || echo 0; }

TOTAL_FOUND=0
report() { # name, size_mb
  TOTAL_FOUND=$(( TOTAL_FOUND + $2 ))
  [ "$PROGRESS" -eq 1 ] && echo "::result $2"
  [ "$2" -gt 0 ] && printf "  %7s MB  %s\n" "$2" "$1"
}
skipped() { printf "  %10s  %s\n" "skipped" "$1"; note "skipped: $1"; }

# Is a build running? Idle Gradle daemons don't count; a gradlew client does.
xcode_busy()  { pgrep -q xcodebuild || pgrep -qf 'XCBBuildService'; }
gradle_busy() { pgrep -qf 'GradleWrapperMain|gradlew'; }

# stale <dir> — true when nothing inside was modified within AGE_H hours.
stale() { [ -z "$(find "$1" -mmin -"$AGE_MIN" -print -quit 2>/dev/null)" ]; }

# Progress protocol (only with --progress), one event per line on stdout:
#   ::total <n>          number of steps that follow
#   ::step <label>       a step starts
#   ::result <mb>        MB the current step found / removed
#   ::note <text>        free-text status for the current step
STEP_COUNT=$(( 10 + DEEP * 5 ))
step() { [ "$PROGRESS" -eq 1 ] && echo "::step $1"; return 0; }
note() { [ "$PROGRESS" -eq 1 ] && echo "::note $1"; return 0; }

# nuke <label> <path>... — one step: report in dry-run, delete otherwise
nuke() { step "$1"; _nuke "$@"; }
_nuke() {
  local label="$1"; shift
  local total=0 p keep=()
  # A symlinked target was relocated on purpose (e.g. to the T9); deleting the
  # link would make tools refill the internal disk.
  for p in "$@"; do [ -L "$p" ] || keep+=("$p"); done
  if [ "${#keep[@]}" -eq 0 ]; then
    note "skipped (symlinked or missing)"
    return 0
  fi
  set -- "${keep[@]}"
  for p in "$@"; do total=$(( total + $(size_mb "$p") )); done
  report "$label" "$total"
  [ "$DRY" -eq 1 ] && return 0
  for p in "$@"; do rm -rf "$p" 2>/dev/null; done
}

# nuke_stale <label> <dir>... — like nuke, but only the dirs that are stale.
nuke_stale() { step "$1"; _nuke_stale "$@"; }
_nuke_stale() {
  local label="$1"; shift
  local old=() fresh=0 d
  for d in "$@"; do
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    if stale "$d"; then old+=("$d"); else fresh=$(( fresh + 1 )); fi
  done
  [ "$fresh" -gt 0 ] && skipped "$label: $fresh in use (touched < ${AGE_H}h)"
  if [ "${#old[@]}" -gt 0 ]; then
    _nuke "$label (${#old[@]} dirs)" "${old[@]}"
  elif [ "$fresh" -eq 0 ]; then
    note "nothing found"
  fi
  return 0
}

# One run at a time: the hourly LaunchAgent and DiskCleaner.app share this.
LOCK="/tmp/disk-cleanup.lock"
if [ "$DRY" -eq 0 ]; then
  if ! mkdir "$LOCK" 2>/dev/null; then
    # A lock older than 2h means a crashed run; anything newer is a live one.
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
      rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0
    else
      echo "$(date '+%Y-%m-%d %H:%M')  already running, skipped" ; exit 0
    fi
  fi
  trap 'rm -rf "$LOCK"' EXIT
fi

before=$(free_mb)
[ "$DRY" -eq 1 ] && echo "DRY RUN — nothing will be deleted"
[ "$PROGRESS" -eq 1 ] && echo "::total $STEP_COUNT"

### ---------- safe targets ----------

# Xcode derived data, per project, so active projects keep their incremental build.
if xcode_busy; then
  step "Xcode DerivedData"
  skipped "Xcode DerivedData: xcodebuild is running"
else
  nuke_stale "Xcode DerivedData" "$HOME/Library/Developer/Xcode/DerivedData"/*/
fi
# Device symbol caches: regenerated when a device reconnects.
nuke "Xcode DeviceSupport"    "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
# Simulator logs grow unbounded — seen at 434 MB.
nuke "CoreSimulator logs"     "$HOME/Library/Logs/CoreSimulator"
# npm's content-addressed cache: re-populated on next install.
nuke "npm cache"              "$HOME/.npm/_cacache"
# App updater leftovers + CocoaPods spec cache.
nuke "App updater leftovers"  "$HOME/Library/Caches"/*.ShipIt "$HOME/Library/Caches/CocoaPods"

# Per-project build output inside repos and worktrees. Only dirs proven to be
# Gradle/Xcode/Next output — never a bare directory that merely reads "build".
step "Project build output"
if [ -d "$HACKING" ]; then
  note "scanning ${HACKING}…"
  BUILD_LIST="$(mktemp -t diskclean)"
  (
    cd "$HACKING" || exit 0
    {
      find . -type d -name build -prune 2>/dev/null \
        | grep -v -e /node_modules/ -e /\.venv/ \
        | while read -r d; do
            compgen -G "$(dirname "$d")/build.gradle*" >/dev/null && echo "$PWD/${d#./}"
          done
      find . -type d -name build -prune 2>/dev/null \
        | grep -v -e /node_modules/ -e /\.venv/ | grep -iE "(_ios|/ios)/build$" \
        | sed "s#^\.#$PWD#"
      find . -type d \( -name .next -o -name .gradle -o -name __pycache__ -o -name .pytest_cache \) -prune 2>/dev/null \
        | grep -v -e /node_modules/ -e /\.venv/ | sed "s#^\.#$PWD#"
    } | sort -u
  ) > "$BUILD_LIST"

  BUILD_DIRS=()
  while IFS= read -r d; do
    # A running build may be writing into any Gradle or Xcode output dir.
    if gradle_busy && { [ "${d##*/}" = .gradle ] || compgen -G "${d%/*}/build.gradle*" >/dev/null; }; then continue; fi
    if xcode_busy && [[ "$d" =~ (_ios|/ios)/build$ ]]; then continue; fi
    BUILD_DIRS+=("$d")
  done < "$BUILD_LIST"
  rm -f "$BUILD_LIST"
  gradle_busy && skipped "Gradle build output: a Gradle build is running"
  xcode_busy  && skipped "iOS build output: xcodebuild is running"
  if [ "${#BUILD_DIRS[@]}" -gt 0 ]; then
    _nuke_stale "Project build output" "${BUILD_DIRS[@]}"
  else
    note "nothing found"
  fi
else
  note "skipped ($HACKING not found)"
fi

# Docker build cache older than 3 days. Only if the daemon is up; images/volumes untouched.
step "Docker build cache"
# A wedged Docker Desktop makes `docker info` hang forever, so cap it at 10s.
docker_up() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 &
  local pid=$! i
  for i in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null || { wait "$pid"; return $?; }
    sleep 0.5
  done
  kill "$pid" 2>/dev/null
  return 1
}
if docker_up; then
  if [ "$DRY" -eq 1 ]; then
    dc=$(docker system df --format '{{.Type}}|{{.Reclaimable}}' 2>/dev/null \
         | awk -F'|' '/Build Cache/{print $2}')
    [ -n "${dc:-}" ] && printf "  %10s  Docker build cache (only entries > 72h are pruned)\n" "$dc"
  else
    docker builder prune -af --filter until=72h >/dev/null 2>&1
  fi
else
  note "skipped (Docker not running or not responding)"
fi

# pnpm store: drops packages no longer referenced by any project.
step "pnpm store prune"
if command -v pnpm >/dev/null 2>&1 && [ "$DRY" -eq 0 ]; then
  pnpm store prune >/dev/null 2>&1
else
  note "skipped"
fi

# Claude worktrees whose PR is merged or closed. Removed only when the PR's last
# commit is exactly HEAD (nothing unpushed), the tree is clean, git hasn't
# touched it for AGE_H hours and no process has it as working directory.
# --force is only reached after the checks above (it would otherwise trip on build dirs).
step "Merged-PR worktrees"
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && [ -d "$HACKING" ]; then
  CWDS="$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sort -u)"
  wt_n=0; wt_mb=0; wt_skip=0
  while read -r wtdir; do
    repo="${wtdir%/.claude/worktrees}"
    slug=$(git -C "$repo" remote get-url origin 2>/dev/null \
      | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//')
    [ -n "$slug" ] || continue
    prs=$(gh pr list --repo "$slug" --state all --limit 1000 \
      --json headRefName,headRefOid,state 2>/dev/null) || continue
    for p in "$wtdir"/*/; do
      p="${p%/}"
      [ -d "$p" ] && [ ! -L "$p" ] || continue
      b=$(git -C "$p" symbolic-ref --short -q HEAD) || continue   # detached: leave it
      h=$(git -C "$p" rev-parse HEAD 2>/dev/null) || continue
      done_pr=$(jq -r --arg b "$b" --arg h "$h" '[.[] | select(.headRefName == $b
        and .headRefOid == $h and (.state == "MERGED" or .state == "CLOSED"))] | length' <<<"$prs")
      [ "${done_pr:-0}" -gt 0 ] || continue
      gd=$(git -C "$p" rev-parse --absolute-git-dir 2>/dev/null)
      # Untracked build/venv dirs left by sessions don't count as work.
      if [ -n "$(git -C "$p" status --porcelain 2>/dev/null \
            | grep -vE '^\?\? (\.dd[^/]*|\.venv[^/]*|build|\.next|\.gradle)/$')" ] \
        || printf '%s\n' "$CWDS" | grep -qE "^$(printf '%s' "$p" | sed 's/[.[\*^$]/\\&/g')(/|$)" \
        || [ -n "$(find "$gd/index" "$gd/logs/HEAD" -mmin -"$AGE_MIN" 2>/dev/null)" ]; then
        wt_skip=$(( wt_skip + 1 )); continue
      fi
      mb=$(size_mb "$p")
      if [ "$DRY" -eq 0 ] && ! git -C "$repo" worktree remove --force "$p" 2>/dev/null; then
        wt_skip=$(( wt_skip + 1 )); continue
      fi
      wt_n=$(( wt_n + 1 )); wt_mb=$(( wt_mb + mb ))
    done
  done < <(find "$HACKING" -maxdepth 5 -type d -path '*/.claude/worktrees' -prune 2>/dev/null)
  [ "$wt_n" -gt 0 ] && report "Merged-PR worktrees ($wt_n)" "$wt_mb"
  [ "$wt_skip" -gt 0 ] && skipped "Merged-PR worktrees: $wt_skip dirty, recent or in use"
else
  note "skipped (needs gh, jq and $HACKING)"
fi

# Tidy stale worktree registry entries (metadata only, frees no real space).
step "Prune stale git worktrees"
if [ "$DRY" -eq 0 ] && [ -d "$HACKING" ]; then
  while read -r g; do
    git -C "$(dirname "$g")" worktree prune 2>/dev/null
  done < <(find "$HACKING" -maxdepth 4 -type d -name .git -prune 2>/dev/null)
fi

### ---------- --deep targets ----------
# Correct but slow to refetch, so off by default.
if [ "$DEEP" -eq 1 ]; then
  # Gradle prunes its own cache after 30 days unused; wiping it means a full re-download.
  if gradle_busy; then
    step "Gradle caches (slow refetch)"
    skipped "Gradle caches: a Gradle build is running"
  else
    nuke "Gradle caches (slow refetch)"    "$HOME/.gradle/caches"
  fi
  nuke "HuggingFace models (slow refetch)" "$HOME/.cache/huggingface"
  nuke "Codex runtimes"                    "$HOME/.cache/codex-runtimes"
  nuke "torch cache"                       "$HOME/.cache/torch"
  step "yarn cache clean"
  command -v yarn >/dev/null 2>&1 && [ "$DRY" -eq 0 ] && yarn cache clean >/dev/null 2>&1
fi

after=$(free_mb)
if [ "$DRY" -eq 1 ]; then
  printf "\nreclaimable: ~%d GB   |   free now: %d GB\n" "$(( TOTAL_FOUND / 1024 ))" "$(( after / 1024 ))"
else
  line=$(printf "%s  freed %d GB  |  free now: %d GB" \
    "$(date '+%Y-%m-%d %H:%M')" "$(( (after - before) / 1024 ))" "$(( after / 1024 ))")
  echo "$line" >> "$LOG"
  echo "$line"
fi
