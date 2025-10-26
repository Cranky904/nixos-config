{ config, pkgs, ... }:

{
  programs.nixvim = {
    enable = true;

    plugins.lsp.enable = true;
    plugins.cmp.enable = true;

    plugins.lsp.servers = {
      rust_analyzer.enable = true;
      rust_analyzer.installCargo = false;
      rust_analyzer.installRustc= false;

      gopls.enable = true;
      zls.enable = true;
      nil_ls.enable = true;
      clangd.enable = true;
      ts_ls.enable = true;
      eslint.enable = true;
      tailwindcss.enable = true;
    };

    colorschemes.gruvbox.enable = true;
    colorschemes.gruvbox.settings.transparent_background = true;

    plugins = {
      lualine.enable = true;
      telescope.enable = true;
      treesitter.enable = true;
      which-key.enable = true;
      web-devicons.enable = true;
      nvim-tree.enable = true;

      gitsigns.enable = true;
      comment.enable = true;
      vim-surround.enable = true;
    };

    keymaps = [
      {
        mode = "n";
        key = "<C-n>";
        action = "<cmd>NvimTreeToggle<cr>";
        options = { noremap = true; silent = true; desc = "Toggle file explorer"; };
      }
      {
        mode = "n";
        key = "<leader>ff";
        action = "<cmd>Telescope find_files<cr>";
        options = { noremap = true; silent = true; desc = "Find files"; };
      }
      {
        mode = "n";
        key = "<leader>fg";
        action = "<cmd>Telescope live_grep<cr>";
        options = { noremap = true; silent = true; desc = "Live grep"; };
      }
    ];

    extraConfigLua = ''
      vim.opt.number = true
      vim.opt.relativenumber = true
      vim.opt.clipboard = 'unnamedplus'

      vim.opt.expandtab = true
      vim.opt.shiftwidth = 2
      vim.opt.tabstop = 2
      vim.opt.softtabstop = 2

      vim.opt.incsearch = true
      vim.opt.ignorecase = true
      vim.opt.smartcase = true

      vim.opt.lazyredraw = true
      vim.opt.termguicolors = true
      vim.opt.updatetime = 300


      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1

      pcall(function()
        require('lualine').setup({ options = { theme = 'gruvbox' } })
      end)

      pcall(function() require('gitsigns').setup{} end)

      pcall(function() require('Comment').setup{} end)
    '';
  };
}
