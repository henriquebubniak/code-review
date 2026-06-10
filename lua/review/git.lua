local M = {}

---Run a git command in the current working directory and return stdout.
---Raises on non-zero exit.
---@param args string[]
---@return string
function M.exec(args)
  local cmd = vim.list_extend({ "git" }, args)
  local result = vim.system(cmd, { text = true }):wait()
  if result.code ~= 0 then
    error(("git %s: %s"):format(table.concat(args, " "), vim.trim(result.stderr or "")), 0)
  end
  return result.stdout or ""
end

---@return boolean
function M.in_repo()
  local result = vim.system({ "git", "rev-parse", "--is-inside-work-tree" }, { text = true }):wait()
  return result.code == 0
end

---@class review.Commit
---@field hash string
---@field date string
---@field author string
---@field subject string

---Recent commits reachable from `rev`, newest first.
---@param rev string branch name or any revision
---@param max integer
---@return review.Commit[]
function M.commits(rev, max)
  local out = M.exec({
    "log",
    rev,
    "--pretty=format:%h%x09%ad%x09%an%x09%s",
    "--date=short",
    "-n",
    tostring(max),
  })
  local commits = {}
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local hash, date, author, subject = line:match("^(%S+)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if hash then
      commits[#commits + 1] = { hash = hash, date = date, author = author, subject = subject }
    end
  end
  return commits
end

---@class review.Branch
---@field name string short ref name, e.g. "main" or "origin/main"
---@field date string date of the branch tip commit
---@field subject string subject of the branch tip commit

---Local and remote branches, most recently committed first.
---@return review.Branch[]
function M.branches()
  local out = M.exec({
    "for-each-ref",
    "--sort=-committerdate",
    "--format=%(refname)%09%(refname:short)%09%(committerdate:short)%09%(subject)",
    "refs/heads",
    "refs/remotes",
  })
  local branches = {}
  for line in vim.gsplit(out, "\n", { plain = true, trimempty = true }) do
    local refname, short, date, subject = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    -- skip symbolic refs like refs/remotes/origin/HEAD (whose short name is just "origin")
    if refname and not refname:match("/HEAD$") then
      branches[#branches + 1] = { name = short, date = date, subject = subject }
    end
  end
  return branches
end

---Full hash of the merge-base of two revisions, or nil if there is none.
---@param a string
---@param b string
---@return string|nil
function M.merge_base(a, b)
  local ok, out = pcall(M.exec, { "merge-base", a, b })
  if not ok then
    return nil
  end
  out = vim.trim(out)
  return out ~= "" and out or nil
end

---One-line description of a revision: "<short-hash>  <subject>".
---@param rev string
---@return string
function M.describe(rev)
  return vim.trim(M.exec({ "log", "-1", "--pretty=format:%h  %s", rev }))
end

---Name of the currently checked-out branch, or nil when HEAD is detached.
---@return string|nil
function M.current_branch()
  local name = vim.trim(M.exec({ "rev-parse", "--abbrev-ref", "HEAD" }))
  if name == "" or name == "HEAD" then
    return nil
  end
  return name
end

---@return boolean
function M.has_uncommitted_changes()
  local out = M.exec({ "status", "--porcelain" })
  return vim.trim(out) ~= ""
end

return M
