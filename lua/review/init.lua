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

---Open diffview for the given range.
---@param base string
---@param target string|nil a revision, picker.WORKTREE, or nil — both mean dirty working tree
function M.diff(base, target)
  local picker = require("review.picker")
  local arg
  if target == nil or target == picker.WORKTREE then
    -- ":DiffviewOpen <rev>" diffs <rev> against the working tree, dirty changes included
    arg = base
  else
    arg = base .. M.config.range_symbol .. target
  end
  local ok, err = pcall(vim.cmd.DiffviewOpen, arg)
  if not ok then
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
    { prompt = "Base (old) revision", include_worktree = false, config = M.config },
    function(b)
      if not b then
        return
      end
      picker.select(
        { prompt = ("Target (new) revision — %s%s?"):format(b, M.config.range_symbol), include_worktree = true, config = M.config },
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
