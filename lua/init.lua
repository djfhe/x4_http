local function initLibs()
  package.path = package.path ..
      ";extensions/djfhe_http/lua/?.lua";
  -- the load order is important for luasec
  local libs = {
    {
      name = "luasocket.socket.core",
      path = "extensions/djfhe_http/lua/luasocket/core.dll",
      func = "luaopen_socket_core",
    },
    {
      name = "luasocket.mime.core",
      path = "extensions/djfhe_http/lua/luasocket/mime.dll",
      func = "luaopen_mime_core",
    },
    {
      name = "luasec.core",
      path = "extensions/djfhe_http/lua/luasec/ssl.dll",
      func = "luaopen_ssl_core",
    },
    {
      name = "luasec.context",
      path = "extensions/djfhe_http/lua/luasec/ssl.dll",
      func = "luaopen_ssl_context",
    },
    {
      name = "luasec.x509",
      path = "extensions/djfhe_http/lua/luasec/ssl.dll",
      func = "luaopen_ssl_x509",
    },
    {
      name = "luasec.config",
      path = "extensions/djfhe_http/lua/luasec/ssl.dll",
      func = "luaopen_ssl_config",
    },
  }

  for _, lib in ipairs(libs) do
    if package.loaded[lib.name] then
      goto continue
    end

    local f, err = package.loadlib(lib.path, lib.func)
    if not f then
      error("Failed to load '" .. lib.path .. "': " .. tostring(err))
    end

    -- Load the module into the package.loaded table
    package.loaded[lib.name] = f()

    ::continue::
  end
end

---@type number # The last time the client was updated in seconds
---@diagnostic disable-next-line: assign-type-mismatch
local lastClientUpdate = GetCurRealTime()

local function onClientUpdate()
  local currentTime = GetCurRealTime()
  local deltaTime = currentTime - lastClientUpdate
  ---@diagnostic disable-next-line: cast-local-type
  lastClientUpdate = currentTime

  if (deltaTime < 0.05) then
    -- We need to do this additional check, since sinza will influence the update interval
    return
  end

  local client = require("djfhe.http.client")
  client.update()
end

function Init()
  initLibs()
  RegisterEvent("djfhe.http.client.update", onClientUpdate)
end

Init()

return
