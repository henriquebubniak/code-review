local git = require("review.git")

local M = {}

---Sentinel meaning "the dirty working tree" was chosen as the target revision.
M.WORKTREE = "review.worktree"

---Floating list window shared by the commit and branch pickers.
---@param opts { title: string, footer: string, matches: [string, string][], on_close: fun() }
local function float_list(opts)
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
    title = opts.title,
    title_pos = "center",
    footer = opts.footer,
    footer_pos = "center",
  }
  local win = vim.api.nvim_open_win(buf, true, win_config)
  vim.wo[win].cursorline = true
  for _, m in ipairs(opts.matches) do
    vim.fn.matchadd(m[1], m[2], 10, -1, { window = win })
  end

  local ui = { buf = buf, win = win }

  function ui.set_lines(lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  function ui.set_title(title)
    win_config.title = title
    vim.api.nvim_win_set_config(win, win_config)
  end

  ---@return integer 1-based cursor row
  function ui.row()
    return vim.api.nvim_win_get_cursor(win)[1]
  end

  function ui.set_row(row)
    vim.api.nvim_win_set_cursor(win, { row, 0 })
  end

  function ui.map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end

  function ui.close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- treat the window being closed by any other means as a cancel
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = opts.on_close,
  })

  return ui
end

---Pick a branch from a floating list, same style as the commit picker.
---@param branches review.Branch[]
---@param current string|nil branch the cursor starts on
---@param cb fun(branch: string|nil)
local function branch_select(branches, current, cb)
  local done = false
  local ui
  local function finish(branch)
    if done then
      return
    end
    done = true
    ui.close()
    cb(branch)
  end

  ui = float_list({
    title = " Switch branch ",
    footer = " <CR> select   q cancel ",
    matches = {
      { "Identifier", [[^\S\+]] },
      { "Comment", [[\<\d\d\d\d-\d\d-\d\d\>]] },
    },
    on_close = function()
      finish(nil)
    end,
  })

  local lines = {}
  for i, b in ipairs(branches) do
    lines[i] = ("%-28s  %s  %s"):format(b.name, b.date, b.subject)
  end
  ui.set_lines(lines)
  for i, b in ipairs(branches) do
    if b.name == current then
      ui.set_row(i)
      break
    end
  end

  ui.map("<CR>", function()
    local b = branches[ui.row()]
    if b then
      finish(b.name)
    end
  end)
  ui.map("q", function()
    finish(nil)
  end)
  ui.map("<Esc>", function()
    finish(nil)
  end)
end

---@class review.Entry
---@field kind "worktree"|"commit"
---@field rev string|nil revision usable in a diff range (nil for worktree)
---@field label string

---Entries for one branch: optional worktree line, then its commits newest first.
---The merge-base of the branch and `opts.merge_base_with` is annotated.
---@param branch string
---@param opts { include_worktree: boolean, merge_base_with: string|nil, config: review.Config }
---@return review.Entry[]
local function build_entries(branch, opts)
  local entries = {}
  if opts.include_worktree then
    entries[#entries + 1] = {
      kind = "worktree",
      label = "[working tree]  uncommitted changes",
    }
  end
  local merge_base = opts.merge_base_with and git.merge_base(branch, opts.merge_base_with)
  for _, commit in ipairs(git.commits(branch, opts.config.max_commits)) do
    local marker = ""
    -- commit.hash is the short form, i.e. a prefix of the full merge-base hash
    if merge_base and vim.startswith(merge_base, commit.hash) then
      marker = ("   ● merge-base with %s"):format(opts.merge_base_with)
    end
    entries[#entries + 1] = {
      kind = "commit",
      rev = commit.hash,
      label = ("%s  %s  %-18s %s%s"):format(commit.hash, commit.date, commit.author, commit.subject, marker),
    }
  end
  return entries
end

---Ask the user for a revision via a floating commit picker.
---
---The popup lists the commits of one branch at a time (initially the checked-out
---branch). `<CR>` selects the commit under the cursor; `<Tab>`/`<S-Tab>` cycle
---branches, `b` opens the branch picker, `r` accepts a typed revision,
---`q`/`<Esc>` cancel. When `merge_base_with` is given, the merge-base of the
---listed branch and that revision is marked in the list.
---@param opts { prompt: string, include_worktree: boolean, merge_base_with: string|nil, config: review.Config }
---@param cb fun(rev: string|nil) receives a rev, M.WORKTREE, or nil if cancelled
function M.select(opts, cb)
  local ok, branches = pcall(git.branches)
  if not ok then
    vim.notify("review.nvim: " .. tostring(branches), vim.log.levels.ERROR)
    return cb(nil)
  end

  local state = {
    branch = git.current_branch() or (branches[1] and branches[1].name) or "HEAD",
    entries = {},
  }

  local done = false
  local ui
  local function finish(rev)
    if done then
      return
    end
    done = true
    ui.close()
    cb(rev)
  end

  ui = float_list({
    title = "",
    footer = " <CR> select   <Tab>/b switch branch   r type rev   q cancel ",
    matches = {
      { "Identifier", [[^\x\{7,40}\>]] },
      { "Comment", [[\<\d\d\d\d-\d\d-\d\d\>]] },
      { "Special", "^\\[working tree\\]" },
      { "DiagnosticInfo", [[● merge-base with .*$]] },
    },
    on_close = function()
      finish(nil)
    end,
  })

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
    ui.set_lines(lines)
    ui.set_title((" %s — %s "):format(opts.prompt, state.branch))
    -- start on the first commit, skipping the worktree line when present
    local first_commit = opts.include_worktree and 2 or 1
    ui.set_row(math.max(1, math.min(first_commit, #entries)))
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
      if b.name == state.branch then
        idx = i
        break
      end
    end
    set_branch(branches[(idx - 1 + dir) % #branches + 1].name)
  end

  ui.map("<CR>", function()
    local entry = state.entries[ui.row()]
    if entry then
      finish(entry.kind == "worktree" and M.WORKTREE or entry.rev)
    end
  end)
  ui.map("q", function()
    finish(nil)
  end)
  ui.map("<Esc>", function()
    finish(nil)
  end)
  ui.map("<Tab>", function()
    cycle_branch(1)
  end)
  ui.map("<S-Tab>", function()
    cycle_branch(-1)
  end)
  ui.map("b", function()
    branch_select(branches, state.branch, function(branch)
      if branch then
        set_branch(branch)
      end
    end)
  end)
  ui.map("r", function()
    vim.ui.input({ prompt = "Revision: " }, function(rev)
      rev = rev and vim.trim(rev) or ""
      if rev ~= "" then
        finish(rev)
      end
    end)
  end)

  render()
end

return M
