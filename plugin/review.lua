if vim.g.loaded_review then
  return
end
vim.g.loaded_review = 1

vim.api.nvim_create_user_command("ReviewDiff", function(cmd)
  require("review").open(unpack(cmd.fargs))
end, {
  nargs = "*",
  desc = "Pick base/target revisions and open Diffview (:ReviewDiff [base [target]])",
  complete = function(arglead)
    local ok, branches = pcall(function()
      return require("review.git").branches()
    end)
    if not ok then
      return {}
    end
    local names = {}
    for _, b in ipairs(branches) do
      if vim.startswith(b.name, arglead) then
        names[#names + 1] = b.name
      end
    end
    return names
  end,
})
