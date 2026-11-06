#!/usr/bin/env bash
# disk-cleanup.sh — reclaim regenerable build caches.
#
#   disk-cleanup.sh              clean (safe targets only)
#   disk-cleanup.sh --dry-run    report what each target holds, delete nothing
#   disk-cleanup.sh --deep       also clear slow-to-refetch caches (ML models etc)
#   disk-cleanup.sh --progress   also emit "::" progress lines (for DiskCleaner.app)
#
# Everything here is rebuilt or re-downloaded on demand. It never touches repo
# state, simulators, the Trash, or anything you authored.
set -u

HACKING="${HACKING:-$HOME/Hacking}"
DRY=0; DEEP=0; PROGRESS=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --deep)       DEEP=1 ;;
    --progress)   PROGRESS=1 ;;
    -h|--help)    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

free_mb() { df -m /System/Volumes/Data | tail -1 | awk '{print $4}'; }
size_mb() { [ -e "$1" ] && du -sm "$1" 2>/dev/null | cut -f1 || echo 0; }

TOTAL_FOUND=0
report() { # name, size_mb
  TOTAL_FOUND=$(( TOTAL_FOUND + $2 ))
  [ "$PROGRESS" -eq 1 ] && echo "::result $2"
  [ "$2" -gt 0 ] && printf "  %7s MB  %s\n" "$2" "$1"
}

# Progress protocol (only with --progress), one event per line on stdout:
#   ::total <n>          number of steps that follow
#   ::step <label>       a step starts
#   ::result <mb>        MB the current step found / removed
#   ::note <text>        free-text status for the current step
STEP_COUNT=$(( 10 + DEEP * 4 ))
step() { [ "$PROGRESS" -eq 1 ] && echo "::step $1"; return 0; }
note() { [ "$PROGRESS" -eq 1 ] && echo "::note $1"; return 0; }

# nuke <label> <path>... — report in dry-run, delete otherwise
nuke() {
  local label="$1"; shift
  local total=0 p keep=()
  step "$label"
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

before=$(free_mb)
[ "$DRY" -eq 1 ] && echo "DRY RUN — nothing will be deleted"
[ "$PROGRESS" -eq 1 ] && echo "::total $STEP_COUNT"

### ---------- safe targets ----------

# Xcode derived data: biggest and fastest-regrowing single item.
nuke "Xcode DerivedData"      "$HOME/Library/Developer/Xcode/DerivedData"
# Gradle dependency cache: re-downloaded on next build.
nuke "Gradle caches"          "$HOME/.gradle/caches"
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
  note "scanning $HACKING…"
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

  BUILD_COUNT=$(grep -c . "$BUILD_LIST" 2>/dev/null || echo 0)
  if [ "$BUILD_COUNT" -gt 0 ]; then
    BUILD_MB=$(xargs -I{} du -sm {} < "$BUILD_LIST" 2>/dev/null | awk '{s+=$1} END {print s+0}')
    report "Project build output ($BUILD_COUNT dirs)" "$BUILD_MB"
    [ "$DRY" -eq 0 ] && tr '\n' '\0' < "$BUILD_LIST" | xargs -0 rm -rf 2>/dev/null
  else
    note "nothing found"
  fi
  rm -f "$BUILD_LIST"
else
  note "skipped ($HACKING not found)"
fi

# Docker build cache. Only if the daemon is actually up; images/volumes untouched.
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
    [ -n "${dc:-}" ] && printf "  %10s  Docker build cache\n" "$dc"
  else
    docker builder prune -af >/dev/null 2>&1
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
  printf "%s  freed %d GB  |  free now: %d GB\n" \
    "$(date '+%Y-%m-%d %H:%M')" "$(( (after - before) / 1024 ))" "$(( after / 1024 ))"
fi
