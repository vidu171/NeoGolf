-- golf.lua -- keystroke capture + free target-peek for VimGolf in Neovim.
--
-- Neovim removed Vim's `-W {logfile}` keylog flag, which is why the official
-- vimgolf client can't drive nvim directly. We reconstruct that keylog with
-- vim.on_key: it hands us the raw bytes the user actually typed, which we
-- append to GOLF_KEYLOG. golf.rb then feeds that file to the vimgolf gem's
-- Keylog parser, producing scores identical to the official client for all
-- printable keys, <Esc>, <CR>, <Tab>, and Ctrl-chords.
--
-- Caveat: keys nvim delivers as multi-byte escape sequences (arrows, <F..>)
-- won't byte-match Vim's 0x80-prefixed K_SPECIAL encoding, so their pretty
-- display may differ. The *count* stays accurate for typical golf solutions,
-- which lean on hjkl and normal-mode motions rather than arrow keys.

local keylog = os.getenv("GOLF_KEYLOG")
if not keylog or keylog == "" then
  return
end

local buf = {}

vim.on_key(function(key, typed)
  -- `typed` is the pre-mapping input (what the user physically pressed).
  -- With --noplugin and no user mappings there are none, but prefer `typed`
  -- when present so counts reflect keystrokes, not mapping expansions.
  local bytes = typed
  if bytes == nil or bytes == "" then
    bytes = key
  end
  if bytes and bytes ~= "" then
    buf[#buf + 1] = bytes
  end
end)

-- Flush on exit. VimLeavePre fires before the process tears down.
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    local fh = io.open(keylog, "wb")
    if fh then
      fh:write(table.concat(buf))
      fh:close()
    end
  end,
})

-- ---------------------------------------------------------------------------
-- Free target peek: press <F2> to toggle a floating window showing the target.
-- The <F2> press itself is popped off the keylog the moment the mapping fires,
-- so peeking never adds to your score. F-keys aren't used in real golf, so this
-- stays honest.
-- ---------------------------------------------------------------------------
local target = os.getenv("GOLF_TARGET")

local peek_win, peek_buf

local function target_lines()
  if not target or target == "" then
    return { "(no target file set)" }
  end
  local lines = {}
  for line in io.lines(target) do
    lines[#lines + 1] = line
  end
  if #lines == 0 then lines = { "" } end
  return lines
end

local function toggle_peek()
  -- Discard the trigger key that on_key just recorded, so peeking is free.
  if #buf > 0 then
    table.remove(buf)
  end

  if peek_win and vim.api.nvim_win_is_valid(peek_win) then
    vim.api.nvim_win_close(peek_win, true)
    peek_win = nil
    return
  end

  local lines = target_lines()
  peek_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(peek_buf, 0, -1, false, lines)
  vim.bo[peek_buf].modifiable = false
  vim.bo[peek_buf].bufhidden = "wipe"

  local width = 0
  for _, l in ipairs(lines) do
    if #l > width then width = #l end
  end
  width = math.max(math.min(width + 2, vim.o.columns - 4), 20)
  local height = math.max(math.min(#lines, vim.o.lines - 4), 1)

  peek_win = vim.api.nvim_open_win(peek_buf, false, {
    relative = "editor",
    anchor = "NE",
    row = 1,
    col = vim.o.columns - 1,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " TARGET (F2 to close) ",
    title_pos = "center",
    focusable = false,
    noautocmd = true,
  })
end

-- Map in normal, insert, and visual so you can peek at any time.
vim.keymap.set({ "n", "i", "v" }, "<F2>", function()
  toggle_peek()
  -- Return to whatever mode we were in; the float is non-focusable so the
  -- cursor stays in the work buffer.
end, { silent = true })
