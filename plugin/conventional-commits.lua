if vim.g.loaded_conventional_commits then
  return
end
vim.g.loaded_conventional_commits = true

vim.api.nvim_create_user_command('ConventionalCommit', function()
  require('conventional-commits').commit()
end, { desc = 'Create a conventional commit' })
