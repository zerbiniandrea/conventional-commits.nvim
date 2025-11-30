local M = {}

-- Load gitmojis from JSON file
local function load_gitmojis()
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')
  local gitmoji_path = plugin_root .. '/gitmojis.json'

  local file = io.open(gitmoji_path, 'r')
  if not file then
    vim.notify('Failed to load gitmojis.json', vim.log.levels.ERROR)
    return {}
  end

  local content = file:read('*all')
  file:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    vim.notify('Failed to parse gitmojis.json', vim.log.levels.ERROR)
    return {}
  end

  -- Transform API format to our format
  local emojis = {}
  for _, gitmoji in ipairs(data.gitmojis or {}) do
    table.insert(emojis, {
      key = gitmoji.emoji,
      name = gitmoji.name,
      description = gitmoji.description,
    })
  end

  return emojis
end

-- Default configuration
M.config = {
  commit_types = {
    { key = 'feat', description = 'A new feature' },
    { key = 'fix', description = 'A bug fix' },
    { key = 'docs', description = 'Documentation only changes' },
    { key = 'style', description = 'Code style changes (formatting, etc)' },
    { key = 'refactor', description = 'Code refactoring' },
    { key = 'perf', description = 'Performance improvements' },
    { key = 'test', description = 'Adding or updating tests' },
    { key = 'build', description = 'Build system or dependencies' },
    { key = 'ci', description = 'CI configuration changes' },
    { key = 'chore', description = 'Other changes' },
    { key = 'revert', description = 'Revert a previous commit' },
  },
  emojis = load_gitmojis(),
  show_emoji_step = true,
  show_preview = true,
  border = 'rounded',
}

-- State to track the commit being built
local state = {
  type = nil,
  scope = nil,
  emoji = nil,
  message = nil,
  body = nil,
}

local function setup_highlights()
  -- Get FloatBorder colors but ensure no background
  local float_border = vim.api.nvim_get_hl(0, { name = 'FloatBorder' })
  vim.api.nvim_set_hl(0, 'ConventionalCommitBorder', { fg = float_border.fg, bg = 'NONE' })

  vim.api.nvim_set_hl(0, 'ConventionalCommitSelected', { bg = '#3e4451', bold = true })
  vim.api.nvim_set_hl(0, 'ConventionalCommitDescription', { link = 'Comment' })

  vim.api.nvim_set_hl(0, 'ConventionalCommitModeInsert', { fg = '#282c34', bg = '#98c379', bold = true })
  vim.api.nvim_set_hl(0, 'ConventionalCommitModeNormal', { fg = '#282c34', bg = '#61afef', bold = true })
  vim.api.nvim_set_hl(0, 'ConventionalCommitModeVisual', { fg = '#282c34', bg = '#c678dd', bold = true })
end

local function create_float(opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.6)
  local height = opts.height or math.floor(vim.o.lines * 0.6)

  local row = math.floor(vim.o.lines * 0.1)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'ConventionalCommit'

  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = M.config.border,
    title = opts.title,
    title_pos = 'left',
  }

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  vim.wo[win].winhl = 'Normal:Normal,FloatBorder:ConventionalCommitBorder'
  vim.wo[win].cursorline = false
  vim.wo[win].cursorcolumn = false

  return buf, win
end

local function create_telescope_layout(opts)
  opts = opts or {}
  local width = opts.width or math.floor(vim.o.columns * 0.6)
  local results_height = opts.results_height or math.floor(vim.o.lines * 0.5)
  local prompt_height = 1

  local row = math.floor(vim.o.lines * 0.1)
  local col = math.floor((vim.o.columns - width) / 2)

  local results_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[results_buf].bufhidden = 'wipe'
  vim.bo[results_buf].filetype = 'ConventionalCommit'

  local results_win = vim.api.nvim_open_win(results_buf, false, {
    relative = 'editor',
    width = width,
    height = results_height,
    row = row + prompt_height + 1,
    col = col,
    style = 'minimal',
    border = M.config.border,
    title = opts.title,
    title_pos = 'left',
  })

  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].bufhidden = 'wipe'
  vim.bo[prompt_buf].filetype = 'ConventionalCommit'

  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = 'editor',
    width = width,
    height = prompt_height,
    row = row,
    col = col,
    style = 'minimal',
    border = M.config.border,
    title = opts.prompt_title or ' Search ',
    title_pos = 'left',
  })

  vim.wo[results_win].winhl = 'Normal:Normal,FloatBorder:ConventionalCommitBorder'
  vim.wo[results_win].cursorline = false

  vim.wo[prompt_win].winhl = 'Normal:Normal,FloatBorder:ConventionalCommitBorder'
  vim.wo[prompt_win].cursorline = false

  return {
    prompt_buf = prompt_buf,
    prompt_win = prompt_win,
    results_buf = results_buf,
    results_win = results_win,
  }
end

local function filter_items(items, query)
  if not query or query == '' then
    return items
  end

  local filtered = {}
  local lower_query = query:lower()

  for _, item in ipairs(items) do
    local search_text = item.key .. ' ' .. item.description
    if item.name then
      search_text = search_text .. ' ' .. item.name
    end
    search_text = search_text:lower()
    if search_text:find(lower_query, 1, true) then
      table.insert(filtered, item)
    end
  end

  return filtered
end

local function render_prompt(buf, search_query, prompt_prefix, placeholder)
  vim.bo[buf].modifiable = true

  local prompt_text = (prompt_prefix or '> ')
  local query = search_query or ''
  local cursor_col = #prompt_text + #query

  local display_text
  if query == '' and placeholder then
    display_text = prompt_text .. placeholder
  else
    display_text = prompt_text .. query
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { display_text })

  if query == '' and placeholder then
    local ns_id = vim.api.nvim_create_namespace('conventional_commits_prompt')
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'ConventionalCommitDescription', 0, #prompt_text, -1)
  end

  vim.bo[buf].modifiable = false

  return cursor_col
end

local function truncate_text(text, max_length)
  if #text <= max_length then
    return text
  end
  return text:sub(1, max_length - 1) .. '…'
end

local function render_results(buf, items, selected_idx, is_emoji_list)
  vim.bo[buf].modifiable = true

  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  local lines = {}
  local highlights = {}

  if #items == 0 then
    table.insert(lines, '')
    table.insert(lines, '  No matches found')
    table.insert(lines, '')
  else
    for idx, item in ipairs(items) do
      local prefix = idx == selected_idx and '▶' or ' '

      if is_emoji_list then
        local icon = item.icon or item.key
        local name = item.name and (':' .. item.name .. ':') or ''
        local separator = ' · '
        -- Calculate available space for description (70 is window width)
        local prefix_len = vim.fn.strdisplaywidth(' ' .. prefix .. ' ' .. icon .. '  ' .. name .. separator)
        local max_desc_len = 70 - prefix_len - 2 -- -2 for border
        local description = truncate_text(item.description, max_desc_len)
        local line1 = string.format(' %s %s  %s%s%s', prefix, icon, name, separator, description)

        -- Store line numbers for highlighting (0-indexed)
        if idx == selected_idx then
          table.insert(highlights, { line = #lines, hl = 'ConventionalCommitSelected' })
        else
          if name ~= '' then
            local name_start = #(' ' .. prefix .. ' ' .. icon .. '  ')
            local name_end = name_start + #name
            table.insert(highlights, {
              line = #lines,
              hl = 'ConventionalCommitDescription',
              col_start = name_start,
              col_end = name_end,
            })
          end
        end

        table.insert(lines, line1)
      else
        local line1 = string.format(' %s %s', prefix, item.key)

        local indent = '   '
        local line2 = indent .. item.description

        -- Store line numbers for highlighting (0-indexed)
        if idx == selected_idx then
          table.insert(highlights, { line = #lines, hl = 'ConventionalCommitSelected' })
          table.insert(highlights, { line = #lines + 1, hl = 'ConventionalCommitSelected' })
        else
          table.insert(highlights, { line = #lines + 1, hl = 'ConventionalCommitDescription' })
        end

        table.insert(lines, line1)
        table.insert(lines, line2)
      end
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns_id = vim.api.nvim_create_namespace('conventional_commits')
  for _, hl in ipairs(highlights) do
    if hl.col_start and hl.col_end then
      vim.api.nvim_buf_add_highlight(buf, ns_id, hl.hl, hl.line, hl.col_start, hl.col_end)
    else
      vim.api.nvim_buf_add_highlight(buf, ns_id, hl.hl, hl.line, 0, -1)
    end
  end

  vim.bo[buf].modifiable = false
end

local function select_from_menu(items, title, title_icon, is_emoji_list, placeholder, callback)
  local item_height = is_emoji_list and 1 or 2
  local results_height = math.min(#items * item_height + 2, 30)

  local layout = create_telescope_layout({
    title = ' ' .. (title or 'Select') .. ' ',
    prompt_title = ' ' .. (title_icon or '🔍') .. '  ' .. (title or 'Search') .. ' ',
    width = 70,
    results_height = results_height,
  })

  local selected_idx = 1
  local search_query = ''
  local filtered_items = vim.deepcopy(items)
  local tooltip_win = nil
  local tooltip_buf = nil

  local function update_tooltip()
    -- Close existing tooltip
    if tooltip_win and vim.api.nvim_win_is_valid(tooltip_win) then
      vim.api.nvim_win_close(tooltip_win, true)
      tooltip_win = nil
    end

    if not is_emoji_list or #filtered_items == 0 then
      return
    end

    local selected_item = filtered_items[selected_idx]
    if not selected_item then
      return
    end

    -- Calculate if description would be truncated
    local icon = selected_item.icon or selected_item.key
    local name = selected_item.name and (':' .. selected_item.name .. ':') or ''
    local separator = ' · '
    local prefix_len = vim.fn.strdisplaywidth(' ▶ ' .. icon .. '  ' .. name .. separator)
    local max_desc_len = 70 - prefix_len - 2

    -- Only show tooltip if description is truncated
    if #selected_item.description <= max_desc_len then
      return
    end

    -- Create tooltip buffer
    tooltip_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[tooltip_buf].bufhidden = 'wipe'

    -- Set tooltip content
    vim.api.nvim_buf_set_lines(tooltip_buf, 0, -1, false, { selected_item.description })

    -- Calculate tooltip position (to the right of results window)
    local results_config = vim.api.nvim_win_get_config(layout.results_win)
    local tooltip_col = results_config.col + results_config.width + 2
    local tooltip_width = math.min(50, vim.o.columns - tooltip_col - 2)

    -- Calculate wrapped line count for proper height
    local wrapped_lines = 0
    for char in selected_item.description:gmatch('.') do
      wrapped_lines = wrapped_lines + (char == '\n' and 1 or 0)
    end
    -- Estimate wrapped lines based on width (rough approximation)
    local estimated_lines = math.ceil(#selected_item.description / tooltip_width) + wrapped_lines
    local max_tooltip_height = math.floor(vim.o.lines * 0.6)
    local tooltip_height = math.min(estimated_lines, max_tooltip_height)

    -- Create tooltip window
    tooltip_win = vim.api.nvim_open_win(tooltip_buf, false, {
      relative = 'editor',
      width = tooltip_width,
      height = tooltip_height,
      row = results_config.row,
      col = tooltip_col,
      style = 'minimal',
      border = M.config.border,
      title = ' Description ',
      title_pos = 'left',
    })

    vim.wo[tooltip_win].winhl = 'Normal:Normal,FloatBorder:ConventionalCommitBorder'
    vim.wo[tooltip_win].wrap = true
    vim.wo[tooltip_win].linebreak = true
  end

  local function update_ui()
    local cursor_col = render_prompt(layout.prompt_buf, search_query, '> ', placeholder)
    render_results(layout.results_buf, filtered_items, selected_idx, is_emoji_list)
    vim.api.nvim_win_set_cursor(layout.prompt_win, { 1, cursor_col })

    -- Scroll the results window to show the selected item
    if #filtered_items > 0 then
      local line_in_results = selected_idx
      if not is_emoji_list then
        -- For two-line items (commit types), each item takes 2 lines
        line_in_results = (selected_idx - 1) * 2 + 1
      end
      vim.api.nvim_win_set_cursor(layout.results_win, { line_in_results, 0 })
    end

    update_tooltip()
  end

  update_ui()

  local function close_and_callback(item)
    if tooltip_win and vim.api.nvim_win_is_valid(tooltip_win) then
      vim.api.nvim_win_close(tooltip_win, true)
    end
    vim.api.nvim_win_close(layout.prompt_win, true)
    vim.api.nvim_win_close(layout.results_win, true)
    if callback then
      callback(item)
    end
  end

  local opts = { buffer = layout.prompt_buf, nowait = true, silent = true }

  vim.keymap.set('n', '<Down>', function()
    selected_idx = math.min(selected_idx + 1, #filtered_items)
    update_ui()
  end, opts)

  vim.keymap.set('n', '<Up>', function()
    selected_idx = math.max(selected_idx - 1, 1)
    update_ui()
  end, opts)

  vim.keymap.set('n', '<C-n>', function()
    selected_idx = math.min(selected_idx + 1, #filtered_items)
    update_ui()
  end, opts)

  vim.keymap.set('n', '<C-p>', function()
    selected_idx = math.max(selected_idx - 1, 1)
    update_ui()
  end, opts)

  vim.keymap.set('n', '<CR>', function()
    if #filtered_items > 0 then
      close_and_callback(filtered_items[selected_idx])
    end
  end, opts)

  vim.keymap.set('n', '<Esc>', function()
    close_and_callback(nil)
  end, opts)

  vim.keymap.set('n', 'q', function()
    close_and_callback(nil)
  end, opts)

  local function update_search(new_query)
    search_query = new_query
    filtered_items = filter_items(items, search_query)
    selected_idx = math.min(selected_idx, math.max(1, #filtered_items))
    update_ui()
  end

  vim.keymap.set('n', '<Space>', function()
    update_search(search_query .. ' ')
  end, opts)

  vim.keymap.set('n', '<BS>', function()
    update_search(search_query:sub(1, -2))
  end, opts)

  for i = 0, 9 do
    vim.keymap.set('n', tostring(i), function()
      update_search(search_query .. tostring(i))
    end, opts)
  end

  for i = string.byte('a'), string.byte('z') do
    local char = string.char(i)
    vim.keymap.set('n', char, function()
      update_search(search_query .. char)
    end, opts)

    vim.keymap.set('n', char:upper(), function()
      update_search(search_query .. char:upper())
    end, opts)
  end

  for _, char in ipairs({ '-', '_', '.', '/', ':', '(', ')' }) do
    vim.keymap.set('n', char, function()
      update_search(search_query .. char)
    end, opts)
  end
end

local function input_prompt_simple(title, placeholder, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = 70
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = 1,
    row = math.floor(vim.o.lines * 0.1),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = M.config.border,
    title = title,
    title_pos = 'left',
  })

  vim.wo[win].winhl = 'Normal:Normal,FloatBorder:ConventionalCommitBorder'

  local text = ''
  local function render()
    vim.bo[buf].modifiable = true
    local display = text == '' and placeholder or text
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '> ' .. display })
    if text == '' and placeholder then
      local ns = vim.api.nvim_create_namespace('cc_placeholder')
      vim.api.nvim_buf_add_highlight(buf, ns, 'ConventionalCommitDescription', 0, 2, -1)
    end
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_cursor(win, { 1, 2 + #text })
  end

  render()

  local function close(result)
    vim.api.nvim_win_close(win, true)
    callback(result)
  end

  local map = function(key, fn)
    vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map('<CR>', function()
    close(text)
  end)
  map('<Esc>', function()
    close(placeholder and placeholder:find('Optional') and '' or nil)
  end)
  map('q', function()
    close(placeholder and placeholder:find('Optional') and '' or nil)
  end)
  map('<BS>', function()
    text = text:sub(1, -2)
    render()
  end)
  map('<Space>', function()
    text = text .. ' '
    render()
  end)

  for i = 0, 9 do
    map(tostring(i), function()
      text = text .. i
      render()
    end)
  end
  for i = string.byte('a'), string.byte('z') do
    local c = string.char(i)
    map(c, function()
      text = text .. c
      render()
    end)
    map(c:upper(), function()
      text = text .. c:upper()
      render()
    end)
  end
  local special_chars = {
    '-',
    '_',
    '.',
    ',',
    '!',
    '?',
    ':',
    ';',
    '/',
    '\\',
    '(',
    ')',
    '[',
    ']',
    '{',
    '}',
    '@',
    '#',
    '$',
    '%',
    '^',
    '&',
    '*',
    '+',
    '=',
    '|',
    '<',
    '>',
    '~',
    '`',
    "'",
    '"',
  }
  for _, c in ipairs(special_chars) do
    map(c, function()
      text = text .. c
      render()
    end)
  end
end

local function input_prompt(title, placeholder, is_multiline, initial_value, callback)
  -- Handle optional initial_value parameter
  if type(initial_value) == 'function' then
    callback = initial_value
    initial_value = nil
  end

  local height = is_multiline and 10 or 1
  local width = 70

  local row = math.floor(vim.o.lines * 0.1)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = true

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = M.config.border,
    title = title,
    title_pos = 'left',
  })

  vim.wo[win].winhl = 'Normal:Normal,FloatBorder:ConventionalCommitBorder'
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = true

  local has_placeholder = false

  local function update_mode_indicator()
    local mode = vim.api.nvim_get_mode().mode
    local mode_text
    local mode_hl

    if mode == 'i' then
      mode_text = 'INSERT'
      mode_hl = 'ConventionalCommitModeInsert'
    elseif mode == 'v' or mode == 'V' or mode == '\22' then -- \22 is Ctrl-V (visual block)
      mode_text = 'VISUAL'
      mode_hl = 'ConventionalCommitModeVisual'
    else
      mode_text = 'NORMAL'
      mode_hl = 'ConventionalCommitModeNormal'
    end

    local config = vim.api.nvim_win_get_config(win)
    config.footer = {
      { ' ' .. mode_text .. ' ', mode_hl },
    }
    config.footer_pos = 'right'
    vim.api.nvim_win_set_config(win, config)
  end

  local mode_autocmd = vim.api.nvim_create_autocmd('ModeChanged', {
    buffer = buf,
    callback = function()
      update_mode_indicator()
    end,
  })

  if initial_value and initial_value ~= '' then
    local lines = {}
    for line in (initial_value .. '\n'):gmatch('([^\n]*)\n') do
      table.insert(lines, line)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  elseif placeholder then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { placeholder })
    local ns_id = vim.api.nvim_create_namespace('conventional_commits_input')
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'ConventionalCommitDescription', 0, 0, -1)
    has_placeholder = true
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
  end

  local function clear_placeholder_once()
    if has_placeholder then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })
      has_placeholder = false
    end
  end

  if has_placeholder then
    vim.api.nvim_create_autocmd('InsertEnter', {
      buffer = buf,
      once = true,
      callback = clear_placeholder_once,
    })
  end

  local function get_input_text()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    while #lines > 0 and lines[#lines] == '' do
      table.remove(lines)
    end
    return table.concat(lines, '\n')
  end

  local function close_and_callback(result)
    vim.api.nvim_del_autocmd(mode_autocmd)
    vim.api.nvim_win_close(win, true)
    if callback then
      callback(result)
    end
  end

  update_mode_indicator()

  local opts = { buffer = buf, nowait = true, silent = true }

  local function confirm_input()
    local text = get_input_text()
    if has_placeholder then
      text = ''
    end
    close_and_callback(text)
  end

  vim.keymap.set('n', '<CR>', confirm_input, opts)

  vim.keymap.set('n', '<Esc>', function()
    close_and_callback(placeholder and placeholder:find('Optional') and '' or nil)
  end, opts)

  vim.keymap.set('n', 'q', function()
    close_and_callback(placeholder and placeholder:find('Optional') and '' or nil)
  end, opts)

  vim.keymap.set('i', '<C-c>', function()
    close_and_callback(placeholder and placeholder:find('Optional') and '' or nil)
  end, opts)

  if not is_multiline then
    vim.keymap.set('i', '<CR>', '<Nop>', opts)
  end

  vim.cmd('startinsert!')
end

-- Forward declarations for functions that are called from preview
local step_message
local step_body

local function show_preview_and_commit()
  local commit_msg = state.type

  if state.scope and state.scope ~= '' then
    commit_msg = commit_msg .. '(' .. state.scope .. ')'
  end

  commit_msg = commit_msg .. ': '

  if state.emoji and M.config.show_emoji_step then
    commit_msg = commit_msg .. state.emoji .. ' '
  end

  commit_msg = commit_msg .. state.message

  if state.body and state.body ~= '' then
    commit_msg = commit_msg .. '\n\n' .. state.body
  end

  if M.config.show_preview then
    local width = 70
    local buf, win = create_float({
      title = ' 📋  Commit Preview ',
      height = 15,
      width = width,
    })

    local lines = {}

    table.insert(lines, '')

    for line in commit_msg:gmatch('[^\n]+') do
      table.insert(lines, ' ' .. line)
    end

    table.insert(lines, '')

    local separator_line = #lines
    local actual_width = vim.api.nvim_win_get_width(win)
    table.insert(lines, string.rep('─', actual_width))

    table.insert(lines, '')

    if state.body and state.body ~= '' then
      table.insert(lines, ' e edit  •  b edit body  •  A stage all')
    else
      table.insert(lines, ' e edit  •  b add body  •  A stage all')
    end
    table.insert(lines, ' <CR> commit  •  <Esc> cancel')

    table.insert(lines, '')

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local ns_id = vim.api.nvim_create_namespace('conventional_commits_preview')
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'ConventionalCommitDescription', separator_line, 0, -1)

    -- Highlight help text lines - make entire lines dimmed, then highlight keys
    local help_line_1 = separator_line + 2
    local help_line_2 = separator_line + 3

    vim.api.nvim_buf_add_highlight(buf, ns_id, 'ConventionalCommitDescription', help_line_1, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns_id, 'ConventionalCommitDescription', help_line_2, 0, -1)

    -- Highlight keys by finding patterns in the lines
    local line1_text = vim.api.nvim_buf_get_lines(buf, help_line_1, help_line_1 + 1, false)[1]
    local line2_text = vim.api.nvim_buf_get_lines(buf, help_line_2, help_line_2 + 1, false)[1]

    -- Highlight command keys (single letters at start or after bullets)
    -- Match letter at the beginning: " e edit"
    local first_key_pos = line1_text:match('^%s+()')
    if first_key_pos then
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'Special', help_line_1, first_key_pos - 1, first_key_pos)
    end
    -- Match letters after bullets: "•  b" and "•  A"
    for pos in line1_text:gmatch('•%s+()') do
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'Special', help_line_1, pos - 1, pos)
    end

    -- Highlight anything in angle brackets like <CR>, <Esc>
    for start_pos, end_pos in line2_text:gmatch('()<[^>]+>()') do
      vim.api.nvim_buf_add_highlight(buf, ns_id, 'Special', help_line_2, start_pos - 1, end_pos - 1)
    end

    vim.bo[buf].modifiable = false

    local opts = { buffer = buf, nowait = true, silent = true }

    vim.keymap.set('n', '<CR>', function()
      vim.api.nvim_win_close(win, true)

      vim.fn.system({ 'git', 'commit', '-m', commit_msg })

      if vim.v.shell_error == 0 then
        vim.notify('✓ Commit created successfully!', vim.log.levels.INFO)
      else
        vim.notify('✗ Failed to create commit. Make sure you have staged changes.', vim.log.levels.ERROR)
      end

      state = {}
    end, opts)

    vim.keymap.set('n', 'e', function()
      vim.api.nvim_win_close(win, true)
      step_message(true) -- Pass true for edit mode
    end, opts)

    vim.keymap.set('n', 'b', function()
      vim.api.nvim_win_close(win, true)
      step_body()
    end, opts)

    vim.keymap.set('n', '<Esc>', function()
      vim.api.nvim_win_close(win, true)
      vim.notify('Commit cancelled', vim.log.levels.WARN)
      state = {}
    end, opts)

    vim.keymap.set('n', 'q', function()
      vim.api.nvim_win_close(win, true)
      vim.notify('Commit cancelled', vim.log.levels.WARN)
      state = {}
    end, opts)

    vim.keymap.set('n', 'A', function()
      vim.fn.system({ 'git', 'add', '.' })
      if vim.v.shell_error == 0 then
        vim.notify('✓ Staged all changes (git add .)', vim.log.levels.INFO)
      else
        vim.notify('✗ Failed to stage changes', vim.log.levels.ERROR)
      end
    end, opts)
  else
    vim.fn.system({ 'git', 'commit', '-m', commit_msg })

    if vim.v.shell_error == 0 then
      vim.notify('✓ Commit created successfully!', vim.log.levels.INFO)
    else
      vim.notify('✗ Failed to create commit. Make sure you have staged changes.', vim.log.levels.ERROR)
    end

    state = {}
  end
end

step_body = function()
  input_prompt(' 📄  Commit Body ', 'Optional: Add detailed explanation...', true, state.body or '', function(body)
    state.body = body
    show_preview_and_commit()
  end)
end

step_message = function(edit_mode)
  if edit_mode then
    local full_msg = state.type
    if state.scope and state.scope ~= '' then
      full_msg = full_msg .. '(' .. state.scope .. ')'
    end
    full_msg = full_msg .. ': '
    if state.emoji and M.config.show_emoji_step then
      full_msg = full_msg .. state.emoji .. ' '
    end
    full_msg = full_msg .. (state.message or '')

    input_prompt(' ✏️  Edit Commit Message ', nil, false, full_msg, function(edited)
      if not edited or edited == '' then
        vim.notify('Commit message is required', vim.log.levels.ERROR)
        state = {}
        return
      end

      -- Try to parse the edited message back into components
      -- Format: type(scope): emoji message  OR  type: emoji message  OR  type(scope): message  OR  type: message
      local pattern1 = '^([^(:]+)%(([^)]+)%):%s*(.*)$' -- type(scope): rest
      local pattern2 = '^([^:]+):%s*(.*)$' -- type: rest

      local commit_type, scope, rest = edited:match(pattern1)
      if not commit_type then
        commit_type, rest = edited:match(pattern2)
        scope = nil
      end

      if commit_type and rest then
        state.type = commit_type
        state.scope = scope or ''

        local emoji_pattern = '^([%z\1-\127\194-\244][\128-\191]*) (.+)$'
        local emoji, message = rest:match(emoji_pattern)

        if emoji and message then
          state.emoji = emoji
          state.message = message
        else
          state.emoji = nil
          state.message = rest
        end
      else
        state.message = edited
      end

      show_preview_and_commit()
    end)
  else
    input_prompt_simple(' 💬  Commit Message ', 'Enter a brief description...', function(message)
      if not message or message == '' then
        vim.notify('Commit message is required', vim.log.levels.ERROR)
        state = {}
        return
      end

      state.message = message
      show_preview_and_commit()
    end)
  end
end

local function step_emoji()
  if M.config.show_emoji_step then
    select_from_menu(M.config.emojis, 'Select Emoji', '🎨', true, 'Type to filter emojis...', function(emoji)
      if not emoji then
        vim.notify('Cancelled', vim.log.levels.WARN)
        state = {}
        return
      end

      state.emoji = emoji.key
      step_message()
    end)
  else
    step_message()
  end
end

local function step_scope()
  input_prompt_simple(' 🎯  Scope ', 'Optional: e.g., api, ui, auth...', function(scope)
    state.scope = scope
    step_emoji()
  end)
end

local function step_type()
  select_from_menu(
    M.config.commit_types,
    'Select Commit Type',
    '🔖',
    false,
    'Type to filter commit types...',
    function(commit_type)
      if not commit_type then
        vim.notify('Cancelled', vim.log.levels.WARN)
        return
      end

      state.type = commit_type.key
      step_scope()
    end
  )
end

function M.commit()
  vim.fn.system('git rev-parse --git-dir 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    vim.notify('Not in a git repository', vim.log.levels.ERROR)
    return
  end

  setup_highlights()

  state = {}

  step_type()
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

return M
