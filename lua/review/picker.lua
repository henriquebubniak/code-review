local git = require("review.git")

local M = {}

---Sentinel meaning "the dirty working tree" was chosen as the target revision.
M.WORKTREE = "review.worktree"

---@class review.Entry
---@field kind "worktree"|"branch"|"commit"|"manual"
---@field rev string|nil revision usable in a diff range (nil for worktree/manual)
---@field label string

---Build the list of selectable entries.
---@param opts { include_worktree: boolean, max_commits: integer }
---@return review.Entry[]
function M.entries(opts)
  local entries = {}
  if opts.include_worktree then
    entries[#entries + 1] = {
      kind = "worktree",
      label = "[working tree]  uncommitted changes",
    }
  end
  entries[#entries + 1] = {
    kind = "manual",
    label = "[revision…]     type any rev (tag, sha, HEAD~3, stash@{0}, …)",
  }
  for _, branch in ipairs(git.branches()) do
    entries[#entries + 1] = {
      kind = "branch",
      rev = branch,
      label = (" %-14s %s"):format("[branch]", branch),
    }
  end
  for _, commit in ipairs(git.commits(opts.max_commits)) do
    entries[#entries + 1] = {
      kind = "commit",
      rev = commit.hash,
      label = ("%s  %s  %-18s %s"):format(commit.hash, commit.date, commit.author, commit.subject),
    }
  end
  return entries
end

---Turn a chosen entry into a revision (or WORKTREE sentinel) and call back.
---@param entry review.Entry|nil
---@param cb fun(rev: string|nil)
local function resolve(entry, cb)
  if not entry then
    return cb(nil)
  end
  if entry.kind == "worktree" then
    return cb(M.WORKTREE)
  end
  if entry.kind == "manual" then
    vim.ui.input({ prompt = "Revision: " }, function(rev)
      rev = rev and vim.trim(rev) or ""
      cb(rev ~= "" and rev or nil)
    end)
    return
  end
  cb(entry.rev)
end

---@param entries review.Entry[]
---@param prompt string
---@param cb fun(entry: review.Entry|nil)
local function telescope_select(entries, prompt, cb)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local previewer = previewers.new_termopen_previewer({
    get_command = function(entry)
      local e = entry.value
      if e.kind == "worktree" then
        return { "git", "diff", "--color=always", "HEAD" }
      elseif e.kind == "manual" then
        return { "true" }
      end
      return { "git", "show", "--color=always", "--stat", "--patch", e.rev }
    end,
  })

  pickers
    .new({}, {
      prompt_title = prompt,
      finder = finders.new_table({
        results = entries,
        entry_maker = function(e)
          return { value = e, display = e.label, ordinal = e.label }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewer,
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          actions.close(bufnr)
          cb(selected and selected.value or nil)
        end)
        return true
      end,
    })
    :find()
end

---Ask the user for a revision.
---@param opts { prompt: string, include_worktree: boolean, config: review.Config }
---@param cb fun(rev: string|nil) receives a rev, M.WORKTREE, or nil if cancelled
function M.select(opts, cb)
  local ok, entries = pcall(M.entries, {
    include_worktree = opts.include_worktree,
    max_commits = opts.config.max_commits,
  })
  if not ok then
    vim.notify("review.nvim: " .. tostring(entries), vim.log.levels.ERROR)
    return cb(nil)
  end

  local backend = opts.config.picker
  if backend == "auto" then
    backend = pcall(require, "telescope") and "telescope" or "select"
  end

  if backend == "telescope" then
    telescope_select(entries, opts.prompt, function(entry)
      resolve(entry, cb)
    end)
  else
    vim.ui.select(entries, {
      prompt = opts.prompt,
      format_item = function(e)
        return e.label
      end,
    }, function(entry)
      resolve(entry, cb)
    end)
  end
end

return M
