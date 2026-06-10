local M = {}

---@class review.Config
---@field range_symbol ".."|"..." ".." diffs exactly base→target; "..." diffs target against the merge-base (what a PR shows)
---@field max_commits integer how many commits to list in the picker
M.config = {
  range_symbol = "..",
  max_commits = 300,
}

---@param opts review.Config|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Winbar labels for the two diff panels of the view we are about to open
-- (pending) and of the view currently open (active).
local labels = { pending = nil, active = nil }

---@param prefix string
---@param rev string
---@return string
local function describe(prefix, rev)
  local ok, desc = pcall(require("review.git").describe, rev)
  local text = ("%s %s%s"):format(prefix, rev, ok and ("  (%s)"):format(desc) or "")
  -- winbar text is a statusline expression: neutralize '%' in commit subjects
  return " " .. text:gsub("%%", "%%%%")
end

---Stamp the diff windows of the current diffview with base/target winbars.
local function apply_labels()
  if not labels.active then
    return
  end
  local ok, lib = pcall(require, "diffview.lib")
  local view = ok and lib.get_current_view() or nil
  local layout = view and view.cur_layout
  if not layout then
    return
  end
  for side, text in pairs(labels.active) do
    local win = layout[side]
    if win and win.id and vim.api.nvim_win_is_valid(win.id) then
      vim.wo[win.id].winbar = text
    end
  end
end

local augroup
local function ensure_autocmds()
  if augroup then
    return
  end
  augroup = vim.api.nvim_create_augroup("ReviewDiffLabels", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "DiffviewViewOpened",
    callback = function()
      -- only label views opened through review.nvim
      labels.active = labels.pending
      labels.pending = nil
      vim.schedule(apply_labels)
    end,
  })
  -- diff windows/buffers change as files are cycled; re-stamp each time
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "DiffviewDiffBufWinEnter",
    callback = vim.schedule_wrap(apply_labels),
  })
  vim.api.nvim_create_autocmd("User", {
    group = augroup,
    pattern = "DiffviewViewClosed",
    callback = function()
      labels.active = nil
    end,
  })
end

---Open diffview for the given range.
---@param base string
---@param target string|nil a revision, picker.WORKTREE, or nil — both mean dirty working tree
function M.diff(base, target)
  local picker = require("review.picker")
  local arg, target_label
  if target == nil or target == picker.WORKTREE then
    -- ":DiffviewOpen <rev>" diffs <rev> against the working tree, dirty changes included
    arg = base
    target_label = " TARGET: working tree (uncommitted changes)"
  else
    arg = base .. M.config.range_symbol .. target
    target_label = describe("TARGET:", target)
  end

  ensure_autocmds()
  labels.pending = { a = describe("BASE:", base), b = target_label }

  local ok, err = pcall(vim.cmd.DiffviewOpen, arg)
  if not ok then
    labels.pending = nil
    vim.notify("review.nvim: DiffviewOpen failed — is diffview.nvim installed?\n" .. tostring(err), vim.log.levels.ERROR)
  end
end

---Entry point. With no args, interactively pick base then target.
---@param base string|nil
---@param target string|nil
function M.open(base, target)
  if base then
    return M.diff(base, target)
  end

  local git = require("review.git")
  local picker = require("review.picker")

  if not git.in_repo() then
    vim.notify("review.nvim: not inside a git repository", vim.log.levels.ERROR)
    return
  end

  picker.select(
    { prompt = "Base (old) revision", include_worktree = false, merge_base_with = "HEAD", config = M.config },
    function(b)
      if not b then
        return
      end
      picker.select(
        { prompt = ("Target (new) revision — %s%s?"):format(b, M.config.range_symbol), include_worktree = true, merge_base_with = b, config = M.config },
        function(t)
          if not t then
            return
          end
          M.diff(b, t)
        end
      )
    end
  )
end

return M
