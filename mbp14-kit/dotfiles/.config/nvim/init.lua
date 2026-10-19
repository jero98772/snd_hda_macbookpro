-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Plugins
require("lazy").setup({
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
  },
})

-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true

-- Setup nvim-tree
require("nvim-tree").setup()

-- Keybinding: toggle tree
vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>")

