#!/usr/bin/env bash
#
# play.sh -- play a real vimgolf.com challenge in Neovim.
#
# Picks a random current challenge (or one you name), opens it in an isolated
# nvim (your LazyVim config is NOT loaded, for fair scoring), counts keystrokes
# exactly like the official client, then loops: submit / retry / diff / quit.
#
# Usage:
#   ./play.sh                 # random challenge from vimgolf.com's front page
#   ./play.sh <challenge_id>  # a specific challenge
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${GOLFHOST:-https://www.vimgolf.com}"
NVIM="${GOLFVIM:-nvim}"

command -v ruby >/dev/null || { echo "error: ruby not found" >&2; exit 1; }
command -v "$NVIM" >/dev/null || { echo "error: $NVIM not found" >&2; exit 1; }

# --- colors -------------------------------------------------------------------
# Disabled automatically when stdout isn't a terminal or NO_COLOR is set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
  C_GREENBG=$'\033[42;30m'; C_REDBG=$'\033[41;37m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_GREEN=; C_RED=; C_YELLOW=; C_CYAN=; C_BLUE=; C_GREENBG=; C_REDBG=
fi

# Colored unified diff of two files: red '-' = your buffer, green '+' = target.
# Falls back gracefully if `diff` produces nothing (shouldn't happen on mismatch).
show_diff() {
  local a="$1" b="$2"
  diff -u --label "your buffer" --label "target" "$a" "$b" \
    | awk -v R="$C_RED" -v G="$C_GREEN" -v C="$C_CYAN" -v D="$C_DIM" -v X="$C_RESET" '
        NR<=2 { next }                                  # skip ---/+++ header lines
        /^@@/  { print C $0 X; next }
        /^-/   { print R $0 X; next }
        /^\+/  { print G $0 X; next }
                { print D $0 X }
      '
}

# --- pick a challenge id ------------------------------------------------------
pick_random_id() {
  # The front page embeds ~50 current challenge ids; sample one.
  curl -s -m 20 "$HOST/" \
    | grep -oE 'challenges/9v00[a-f0-9]+' \
    | sed 's#challenges/##' \
    | sort -u \
    | awk 'BEGIN{srand()} {a[NR]=$0} END{if(NR>0) print a[int(rand()*NR)+1]}'
}

ID="${1:-}"
if [ -z "$ID" ]; then
  echo "Fetching a random challenge from $HOST ..."
  ID="$(pick_random_id)"
  [ -n "$ID" ] || { echo "error: could not find any challenge ids on the front page" >&2; exit 1; }
fi
echo "${C_BOLD}${C_CYAN}Challenge:${C_RESET} $ID"
echo "${C_DIM}Leaderboard: $HOST/challenges/$ID${C_RESET}"

# --- download -----------------------------------------------------------------
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/vimgolf.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# Read the download helper's output lines (work path, target path, type).
# Avoid `mapfile` -- macOS ships bash 3.2 which doesn't have it.
DL_OUT="$(ruby "$HERE/golf.rb" download "$ID" "$WORKDIR")"
WORK="$(printf '%s\n' "$DL_OUT" | sed -n '1p')"
TARGET="$(printf '%s\n' "$DL_OUT" | sed -n '2p')"

# Pristine copy of the starting text so "retry" always resets the buffer.
PRISTINE="$WORKDIR/pristine"
cp "$WORK" "$PRISTINE"

# --- play loop ----------------------------------------------------------------
while :; do
  cp "$PRISTINE" "$WORK"
  KEYLOG="$WORKDIR/keylog"
  rm -f "$KEYLOG"

  # Show the goal before launching so reading it costs no keystrokes.
  echo
  echo "${C_YELLOW}==================== START (you edit this) ====================${C_RESET}"
  cat "$PRISTINE"
  echo "${C_CYAN}==================== TARGET (make it this) ====================${C_RESET}"
  cat "$TARGET"
  echo "${C_DIM}===============================================================${C_RESET}"
  echo "${C_DIM}While editing, press ${C_RESET}${C_YELLOW}F2${C_RESET}${C_DIM} anytime to peek at the target (costs no keystrokes).${C_RESET}"
  printf "${C_BOLD}Press Enter to start editing...${C_RESET} "
  read -r _ </dev/tty || true

  # Isolated nvim: our vimrc, no plugins, no shada, no user config.
  # -u loads golf.vimrc; --cmd runs before that to point the capture module
  # at our keylog and source it.
  GOLF_KEYLOG="$KEYLOG" GOLF_TARGET="$TARGET" "$NVIM" \
    -u "$HERE/golf.vimrc" \
    --noplugin \
    -i NONE \
    --cmd "let \$GOLF_KEYLOG='$KEYLOG'" \
    --cmd "let \$GOLF_TARGET='$TARGET'" \
    --cmd "luafile $HERE/golf.lua" \
    "$WORK"

  if [ ! -f "$KEYLOG" ]; then
    echo "No keystrokes were recorded (did nvim exit abnormally?)."
  fi

  echo
  echo "${C_BOLD}Your keystrokes:${C_RESET}"
  SCORE_LINE="$(ruby "$HERE/golf.rb" score "$KEYLOG" 2>/dev/null || echo $'0\t')"
  COUNT="${SCORE_LINE%%$'\t'*}"
  KEYS="${SCORE_LINE#*$'\t'}"
  echo "  ${C_CYAN}$KEYS${C_RESET}"

  if diff -q "$WORK" "$TARGET" >/dev/null 2>&1; then
    echo
    echo "${C_GREENBG}${C_BOLD}  ✓ SUCCESS  ${C_RESET}${C_GREEN} Your output matches!${C_RESET}"
    echo "${C_GREEN}${C_BOLD}  Score: $COUNT keystrokes${C_RESET}"
    CORRECT=1
  else
    echo
    echo "${C_REDBG}${C_BOLD}  ✗ NO MATCH  ${C_RESET}${C_RED} Buffer doesn't match the target yet.${C_RESET}"
    echo "${C_RED}  Failed-attempt score would be: $COUNT keystrokes.${C_RESET}"
    CORRECT=0
    echo
    echo "${C_BOLD}Difference ${C_RESET}${C_DIM}(${C_RED}- your buffer${C_DIM} vs ${C_GREEN}+ target${C_DIM}):${C_RESET}"
    show_diff "$WORK" "$TARGET"
  fi

  # --- menu -------------------------------------------------------------------
  while :; do
    echo
    if [ "$CORRECT" -eq 1 ]; then
      echo "${C_GREEN}[w]${C_RESET} Upload result and retry   ${C_GREEN}[x]${C_RESET} Upload result and quit"
    fi
    echo "${C_YELLOW}[d]${C_RESET} Show diff (nvim -d)   ${C_YELLOW}[r]${C_RESET} Retry   ${C_YELLOW}[q]${C_RESET} Quit"
    printf "${C_BOLD}Choice>${C_RESET} "
    read -r choice </dev/tty || choice=q

    case "$choice" in
      w|x)
        if [ "$CORRECT" -ne 1 ]; then echo "Can't upload a non-matching entry."; continue; fi
        echo "${C_DIM}Uploading to $HOST ...${C_RESET}"
        STATUS="$(ruby "$HERE/golf.rb" upload "$ID" "$KEYLOG" 2>&1 || true)"
        if [ "$STATUS" = "ok" ]; then
          echo "${C_GREEN}${C_BOLD}✓ Uploaded.${C_RESET} ${C_GREEN}View: $HOST/challenges/$ID${C_RESET}"
        else
          echo "${C_RED}${C_BOLD}✗ Upload failed:${C_RESET} ${C_RED}$STATUS${C_RESET}"
        fi
        [ "$choice" = "x" ] && { echo "Thanks for playing!"; exit 0; }
        break
        ;;
      d)
        "$NVIM" -d -n --noplugin -i NONE "$WORK" "$TARGET"
        ;;
      r)
        break
        ;;
      q)
        echo "Thanks for playing!"
        exit 0
        ;;
      *)
        echo "Unknown choice: $choice"
        ;;
    esac
  done
done
