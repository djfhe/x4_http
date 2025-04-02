---@alias HttpResponseParseState
---| '"status"'
---| '"headers"'
---| '"body"'
---| '"done"'

---@class HttpResponseInstance
---@field protected conn HttpConnectionInstance  # The Connection object
---@field protected status number|nil
---@field protected headers table<string,string>
---@field protected body string
---@field protected parseState HttpResponseParseState
---@field protected contentLength number|nil
---@field protected bytesRead number
local HttpResponseInstance = {}
HttpResponseInstance.__index = HttpResponseInstance

---Construct with a reference to the Connection
---@param conn HttpConnectionInstance
function HttpResponseInstance:new(conn)
  local o = {
    conn          = conn,
    status        = nil,
    headers       = {},
    body          = "",
    parseState    = "status",
    contentLength = nil,
    bytesRead     = 0,

    -- We'll keep partial data we haven't parsed yet
    partialBuffer = "",
  }
  return setmetatable(o, self)
end

function HttpResponseInstance:isDone()
  return self.parseState == 'done'
end

function HttpResponseInstance:getStatus()
  return self.status
end

function HttpResponseInstance:getHeaders()
  return self.headers
end

function HttpResponseInstance:getBody()
  return self.body
end

function HttpResponseInstance:getJson()
  local json = require("jsonlua.json")
  local ok, result = pcall(json.decode, self.body)
  if not ok then
    return nil, "Failed to parse JSON: " .. result
  end
  return result
end

function HttpResponseInstance:isClosed()
  return self.conn:isClosed()
end

function HttpResponseInstance:cancel()
  if self.conn then
    self.conn:close()
  end
end

------------------------------------------------------------------------------
-- Internal parse helpers
------------------------------------------------------------------------------

local function parseStatusLine(self)
  local lineEnd = self.partialBuffer:find("\r\n", 1, true)
  if not lineEnd then
    return false
  end
  local line = self.partialBuffer:sub(1, lineEnd - 1)
  self.partialBuffer = self.partialBuffer:sub(lineEnd + 2)
  local code = line:match("^HTTP/%d%.%d%s+(%d%d%d)")
  if code then
    self.status = tonumber(code)
  else
    self.status = 200 -- fallback
  end
  self.parseState = "headers"
  return true
end

local function parseHeaders(self)
  while true do
    local lineEnd = self.partialBuffer:find("\r\n", 1, true)
    if not lineEnd then
      return false
    end
    local line = self.partialBuffer:sub(1, lineEnd - 1)
    self.partialBuffer = self.partialBuffer:sub(lineEnd + 2)
    if line == "" then
      self.parseState = "body"
      return true
    end

    local key, val = line:match("^(.-):%s*(.*)")
    if key and val then
      key = key:lower()
      if self.headers[key] then
        self.headers[key] = self.headers[key] .. ", " .. val
      else
        self.headers[key] = val
      end
    end
  end
end

local function parseBody(self)
  if not self.contentLength then
    local cl = self.headers["content-length"]
    if cl then
      self.contentLength = tonumber(cl)
    end
  end

  if self.contentLength then
    local need = self.contentLength - self.bytesRead
    if #self.partialBuffer > 0 then
      local take = math.min(need, #self.partialBuffer)
      local chunk = self.partialBuffer:sub(1, take)
      self.body = self.body .. chunk
      self.partialBuffer = self.partialBuffer:sub(take + 1)
      self.bytesRead = self.bytesRead + take
    end
    if #self.body >= self.contentLength then
      self.parseState = "done"
    end
  else
    -- No content-length => read until close or chunked
    -- TODO: is there a better way to detect end of chunked transfer?
  end
end

------------------------------------------------------------------------------
-- The main update loop
------------------------------------------------------------------------------

---@return string|nil error message if any
function HttpResponseInstance:update()
  if self.isDone(self) then
    return
  end

  if self.conn:isClosed() then
    return "Connection closed"
  end

  -- Let the connection do its non-blocking steps: handshake, send, receive
  self.conn:update()

  -- Fetch any new data from the connection buffer
  local newData = self.conn:getData()

  if #newData > 0 then
    -- Append to partialBuffer
    self.partialBuffer = self.partialBuffer .. newData
    -- "consume" it from the connection's buffer
    self.conn:consume(#newData)
  end

  -- Now parse as much as we can
  if self.parseState == "status" then
    parseStatusLine(self)
  end

  if self.parseState == "headers" then
    parseHeaders(self)
  end
  if self.parseState == "body" then
    parseBody(self)
  end
end

return HttpResponseInstance
