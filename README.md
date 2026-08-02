# vimgolf-nvim

Play real [vimgolf.com](https://www.vimgolf.com) challenges in **Neovim**, with
official-client scoring and entry submission — no `:PlayVimGolf` command needed,
just a shell launcher.

## Why this exists

The official `vimgolf` gem drives Vim with `-W {logfile}` to record keystrokes.
**Neovim removed that flag**, so the official client can't score an nvim session.
This project reconstructs the keylog with Neovim's `vim.on_key`, then feeds it to
the *same* `Keylog` parser the gem uses — so scores match the official client.

## Requirements

- `nvim`, `ruby`, `curl`
- The `vimgolf` gem installed (`gem install vimgolf`) — used only for its keylog
  parser.
- A vimgolf.com API key at `~/.vimgolf/config.yaml` (run `vimgolf setup` once) —
  only needed if you want to **submit** entries.

## Usage

```sh
./play.sh                 # random current challenge from vimgolf.com
./play.sh <challenge_id>  # a specific challenge
```

You edit in an **isolated** nvim (your LazyVim config is not loaded, for fair
scoring). On exit you get your keystroke count; then a menu:

- `w` — upload and retry   `x` — upload and quit  (only when your output matches)
- `d` — show a diff of your buffer vs. the target
- `r` — retry (resets the buffer)   `q` — quit

## Files

| File          | Role                                                                 |
|---------------|----------------------------------------------------------------------|
| `play.sh`     | Launcher: pick challenge → isolated nvim → score → submit/retry loop |
| `golf.rb`     | download / score / upload; reuses the vimgolf gem's `Keylog` parser  |
| `golf.lua`    | `vim.on_key` capture — Neovim's replacement for Vim's `-W`           |
| `golf.vimrc`  | leveling config, adapted from `vimgolf.vimrc` for Neovim             |

## Scoring accuracy

Counting is byte-identical to the official client for printable keys, `<Esc>`,
`<CR>`, `<Tab>`, and Ctrl-chords — i.e. essentially all real golf solutions.
Keys nvim emits as multi-byte escape sequences (arrow keys, function keys) may
display differently than Vim's `K_SPECIAL` encoding, though the count stays
right. Good golf avoids those anyway.
