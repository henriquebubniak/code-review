local git = require("review.git")

local M = {}

---Sentinel meaning "the dirty working tree" was chosen as the target revision.
M.WORKTREE = "review.worktree"

---@class review.Entry
---@field kind "worktree"|"commit"
---@field rev string|nil revision usable in a diff range (nil for worktree)
---@field label string

---Entries for one branch: optional worktree line, then its commits newest first.
---@param branch string
---@param opts { include_worktree: boolean, config: review.Config }
---@return review.Entry[]
local function build_entries(branch, opts)
  local entries = {}
  if opts.include_worktree then
    entries[#entries + 1] = {
      kind = "worktree",
      label = "[working tree]  uncommitted changes",
    }
  end
  for _, commit in ipairs(git.commits(branch, opts.config.max_commits)) do
    entries[#entries + 1] = {
      kind = "commit",
      rev = commit.hash,
      label = ("%s  %s  %-18s %s"):format(commit.hash, commit.date, commit.author, commit.subject),
    }
  end
  return entries
end

---Ask the user for a revision via a floating commit picker.
---
---The popup lists the commits of one branch at a time (initially the checked-out
---branch). `<CR>` selects the commit under the cursor; `<Tab>`/`<S-Tab>` cycle
---branches, `b` picks a branch from a menu, `r` accepts a typed revision,
---`q`/`<Esc>` cancel.
---@param opts { prompt: string, include_worktree: boolean, config: review.Config }
---@param cb fun(rev: string|nil) receives a rev, M.WORKTREE, or nil if cancelled
function M.select(opts, cb)
  local ok, branches = pcall(git.branches)
  if not ok then
    vim.notify("review.nvim: " .. tostring(branches), vim.log.levels.ERROR)
    return cb(nil)
  end

  local state = {
    branch = git.current_branch() or branches[1] or "HEAD",
    entries = {},
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "review-picker"

  local width = math.min(110, math.max(40, vim.o.columns - 8))
  local height = math.min(24, math.max(8, vim.o.lines - 6))
  local win_config = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = "",
    title_pos = "center",
    footer = " <CR> select   <Tab>/b switch branch   r type rev   q cancel ",
    footer_pos = "center",
  }
  local win = vim.api.nvim_open_win(buf, true, win_config)
  vim.wo[win].cursorline = true
  vim.fn.matchadd("Identifier", [[^\x\{7,40}\>]], 10, -1, { window = win })
  vim.fn.matchadd("Comment", [[\<\d\d\d\d-\d\d-\d\d\>]], 10, -1, { window = win })
  vim.fn.matchadd("Special", "^\\[working tree\\]", 10, -1, { window = win })

  local done = false
  local function finish(rev)
    if done then
      return
    end
    done = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    cb(rev)
  end

  local function render()
    local ok_entries, entries = pcall(build_entries, state.branch, opts)
    if not ok_entries then
      vim.notify("review.nvim: " .. tostring(entries), vim.log.levels.ERROR)
      return finish(nil)
    end
    state.entries = entries
    local lines = {}
    for i, e in ipairs(entries) do
      lines[i] = e.label
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    win_config.title = (" %s — %s "):format(opts.prompt, state.branch)
    vim.api.nvim_win_set_config(win, win_config)
    -- start on the first commit, skipping the worktree line when present
    local first_commit = opts.include_worktree and 2 or 1
    vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(first_commit, #entries)), 0 })
  end

  local function set_branch(branch)
    state.branch = branch
    render()
  end

  local function cycle_branch(dir)
    if #branches == 0 then
      return
    end
    local idx = 1
    for i, b in ipairs(branches) do
      if b == state.branch then
        idx = i
        break
      end
    end
    set_branch(branches[(idx - 1 + dir) % #branches + 1])
  end

  local function pick_branch()
    vim.ui.select(branches, { prompt = "Branch" }, function(branch)
      if branch then
        set_branch(branch)
      end
    end)
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  map("<CR>", function()
    local entry = state.entries[vim.api.nvim_win_get_cursor(win)[1]]
    if entry then
      finish(entry.kind == "worktree" and M.WORKTREE or entry.rev)
    end
  end)
  map("q", function()
    finish(nil)
  end)
  map("<Esc>", function()
    finish(nil)
  end)
  map("<Tab>", function()
    cycle_branch(1)
  end)
  map("<S-Tab>", function()
    cycle_branch(-1)
  end)
  map("b", pick_branch)
  map("r", function()
    vim.ui.input({ prompt = "Revision: " }, function(rev)
      rev = rev and vim.trim(rev) or ""
      if rev ~= "" then
        finish(rev)
      end
    end)
  end)

  -- treat the window being closed by any other means as a cancel
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      finish(nil)
    end,
  })

  render()
end

return M
