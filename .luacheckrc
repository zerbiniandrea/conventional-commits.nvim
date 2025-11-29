-- Luacheck configuration for Neovim plugin
std = "lua51+luajit"

-- Neovim globals
globals = {
  "vim",
}

-- Ignore some pedantic warnings
ignore = {
  "212", -- Unused argument
  "631", -- Line is too long
}

-- Max line length
max_line_length = 150

-- Exclude patterns
exclude_files = {
  ".luacheckrc",
}
