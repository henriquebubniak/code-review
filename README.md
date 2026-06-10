# review.nvim (working name)

A code-review layer for Neovim, built on [diffview.nvim](https://github.com/sindrets/diffview.nvim).

Diffview renders excellent diffs, but composing the revision range is left to you.
This plugin adds an ergonomic picker: choose a **base** revision, choose a **target**
revision (or the dirty working tree), and the diff opens. Because diffview shows
real buffers on the target side, your LSP works mid-review — jump to definition,
references, hover.

## Requirements

- Neovim ≥ 0.10
- [diffview.nvim](https://github.com/sindrets/diffview.nvim)

## Install (lazy.nvim)

```lua
{
  dir = "/data/henriquebubniak/dev/code-review", -- local checkout
  dependencies = { "sindrets/diffview.nvim" },
  cmd = "ReviewDiff",
  opts = {},
}
```

## Usage

| Command | Effect |
| --- | --- |
| `:ReviewDiff` | Pick base, then target. Target list includes `[working tree]`. |
| `:ReviewDiff <base>` | Diff `<base>` against the dirty working tree. |
| `:ReviewDiff <base> <target>` | Diff `<base>` against `<target>`. |

The picker is a floating window listing the commits of one branch at a time,
starting at the checked-out branch:

| Key | Effect |
| --- | --- |
| `<CR>` | Select the commit under the cursor (or `[working tree]`). |
| `<Tab>` / `<S-Tab>` | Cycle to the next/previous branch (most recently committed first). |
| `b` | Pick a branch from a menu. |
| `r` | Type any revision git understands (`HEAD~3`, tags, `stash@{0}`, …). |
| `q` / `<Esc>` | Cancel. |

`<base>`/`<target>` arguments are tab-completed from branch names.

Inside the resulting view, everything is stock diffview: `<Tab>`/`<S-Tab>` to cycle
files, `:DiffviewToggleFiles` for the panel, `:DiffviewClose` to quit.

## Configuration

```lua
require("review").setup({
  -- ".."  → diff exactly base→target
  -- "..." → diff target against merge-base(base, target), i.e. what a PR shows
  range_symbol = "..",
  max_commits = 300,          -- commits listed in the picker
})
```

## Roadmap

- [ ] Review-state tracking: per-file reviewed flags keyed by blob hash
      (auto-unreviewed when the file changes), persisted across sessions,
      shown in diffview's file panel.
- [ ] Per-line review notes that survive sessions, exportable as Markdown
      for AI assistants.
- [ ] Bitbucket Cloud adapter: pick a PR, check out its branch, draft inline
      comments locally, batch-submit via the REST API, approve.
