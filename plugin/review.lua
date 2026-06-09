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
    return vim.tbl_filter(function(b)
      return vim.startswith(b, arglead)
    end, branches)
  end,
})
