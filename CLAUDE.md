# CLAUDE.md — vimgolf-nvim

Context for AI assistants working on this project. Read this first.

## What this is

A shell-driven way to play **real [vimgolf.com](https://www.vimgolf.com)
challenges in Neovim**, with scoring and entry submission that match the
official client. There is intentionally **no `:PlayVimGolf` command** — the user
wanted a `.sh` launcher, not an nvim plugin command.

Run it:
```sh
./play.sh                 # random current challenge from vimgolf.com
./play.sh <challenge_id>  # a specific challenge
```

## The core problem it solves

The official `vimgolf` gem drives Vim with `-W {logfile}` to record the raw
keystroke byte stream, which it then parses/scores. **Neovim removed the `-W`
flag** (confirmed: `nvim --help` has no `-W`/`-w`). That's the whole reason the
official client can't be used with nvim.

**Our fix:** `golf.lua` uses `vim.on_key` to capture the actually-typed bytes and
writes them to a keylog file on exit. `golf.rb` then feeds that file to the
*same* `VimGolf::Keylog` parser from the installed gem — so scores are identical
to the official client for all printable keys, `<Esc>`, `<CR>`, `<Tab>`, and
Ctrl-chords (i.e. real golf solutions). Multi-byte escape sequences (arrows,
F-keys) won't byte-match Vim's `K_SPECIAL` encoding, so their *display* may
differ, but the count stays right.

## Files

| File          | Role                                                                          |
|---------------|-------------------------------------------------------------------------------|
| `play.sh`     | Launcher. Picks challenge, runs isolated nvim, scores, diff, submit/retry loop. bash **3.2**-compatible (macOS). |
| `golf.rb`     | `download <id> <workdir>` / `score <keylog>` / `upload <id> <keylog>`. Reuses the vimgolf gem's `Keylog` parser. |
| `golf.lua`    | `vim.on_key` keystroke capture + free `<F2>` target-peek float.               |
| `golf.vimrc`  | Leveling config, adapted from the gem's `vimgolf.vimrc` for Neovim.           |
| `README.md`   | User-facing docs.                                                             |

## How it fits together (data flow)

1. `play.sh` gets a challenge id: `$1`, or scraped at random from the
   vimgolf.com front page (`grep -oE 'challenges/9v00[a-f0-9]+'` — there is **no**
   official random API; the front page lists ~50 current ids).
2. `golf.rb download` fetches `$HOST/challenges/<id>.json`
   (`{in:{data,type}, out:{data,type}}`), normalises `\r\n`→`\n`, and writes
   `work.<type>` (edit target), `target.<type>` (desired output), `meta.json`.
   It prints the work path, target path, and type on three lines.
3. `play.sh` copies `work` → `pristine` (for retry resets), prints a colored
   START/TARGET preview, then launches nvim **isolated**:
   `nvim -u golf.vimrc --noplugin -i NONE --cmd "let $GOLF_KEYLOG=..."
   --cmd "let $GOLF_TARGET=..." --cmd "luafile golf.lua" work`.
   The user's real LazyVim config is never loaded → fair scoring by construction
   (this is why install location doesn't affect scoring fairness).
4. On exit, `golf.lua`'s `VimLeavePre` autocmd writes the keylog.
5. `golf.rb score` prints `<count>\t<pretty keystrokes>`.
6. `play.sh` compares buffer to target with `diff -q`. Match → green success +
   offer upload. No match → red banner + **automatic colored diff**.
7. `golf.rb upload` POSTs the raw keylog + apikey to `$HOST/entry.json`.

## Key facts / environment

- Scoring parity relies on the installed `vimgolf` gem
  (`/opt/homebrew/lib/ruby/gems/.../vimgolf-0.5.0`). `golf.rb` requires
  `vimgolf/keylog` and also `require 'strscan'` itself (the gem's keylog.rb
  depends on its parent file to load StringScanner; loading keylog standalone
  needs the explicit require).
- API key for submission lives at `~/.vimgolf/config.yaml` (`vimgolf setup`).
  The user already has one. Upload is the one path not auto-tested (needs a TTY
  and would post to the real leaderboard).
- macOS bash is **3.2** — no `mapfile`/`readarray`, no `declare -A`, no `${x^^}`.
  Keep `play.sh` portable; parse multi-line command output with `sed -n 'Np'`.
- Colors auto-disable when stdout isn't a TTY or `NO_COLOR` is set.

## The `<F2>` target-peek (important design point)

`golf.lua` maps `<F2>` (normal/insert/visual) to toggle a non-focusable float
showing the target. **It must not cost keystrokes.** Verified: one `<F2>` press
produces exactly one `vim.on_key` event (bytes `\x80\x6b\x32`) and the mapping
fires *after* that event, so the handler does `table.remove(buf)` to discard the
recorded trigger before opening the float. If you change the peek key, re-verify
that one press = one on_key event, or the subtraction will be wrong.

## Testing without a TTY

- Score parity: `printf 'ihello\x1b:wq\r' > /tmp/k && ruby golf.rb score /tmp/k`
  → `11  ihello<Esc>:wq<CR>`.
- Full nvim capture: drive headless nvim with `vim.api.nvim_feedkeys` in a
  `--cmd "luafile drive.lua"`, background it, and `( sleep 15; kill -9 $PID )` as
  a watchdog (**macOS has no `timeout`**). Feeding escape sequences via `-s
  scriptfile` can hang the terminal — prefer `feedkeys`.

## Conventions

- User is on macOS + LazyVim; keep everything isolated from their config.
- No new nvim user command; the launcher is the interface.
- Match the existing comment density and style in each file.

## Ideas / not yet done

- Live upload has not been exercised end-to-end (see above).
- Could add: par/leaderboard display, difficulty filtering, a persistent
  side-split target view (would need focus-locking to stay score-free).
