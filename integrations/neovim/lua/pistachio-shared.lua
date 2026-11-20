local M = {}

function M.setup()
  local config = vim.env.XDG_CONFIG_HOME
  if not config or config == "" then config = vim.fn.expand("~/.config") end
  local path = config .. "/pistachio/shared-theme"
  local previous
  local function refresh()
    local file = io.open(path, "r")
    local value = file and file:read("*l") or "pistachio"
    if file then file:close() end
    if value ~= "noir" then value = "pistachio" end
    if value == previous then return end
    previous = value
    vim.g.pistachio_shared_scheme = value
    vim.cmd.colorscheme("pistachio-noir")
  end
  refresh()
  local timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(refresh))
  vim.api.nvim_create_autocmd("VimLeavePre", { once = true, callback = function() timer:stop(); timer:close() end })
end

return M
