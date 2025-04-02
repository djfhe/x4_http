local socket                   = require("luasocket.socket.core")
local ssl                      = require("luasec.ssl")

---@alias HttpConnectionState
---| '"CONNECTING"'
---| '"HANDSHAKE"'
---| '"READY"'
---| '"CLOSED"'

---@class HttpConnectionInstance
---@field protected host string
---@field protected port number
---@field protected useSSL boolean
---@field protected sock table|nil              # The underlying LuaSocket or LuaSec socket
---@field protected state HttpConnectionState
---@field protected sendQueue string[]          # Data waiting to be sent
---@field protected bytesSent integer           # Total bytes ever sent on this connection
---@field protected totalReceived integer       # How many bytes we have already read from the socket
---@field protected recvBuffer string           # Accumulated data from the socket
---@field protected errMsg string|nil           # If we transition to CLOSED, store the reason here
local HttpConnectionInstance   = {}
HttpConnectionInstance.__index = HttpConnectionInstance

-- Default TLS params.
local defaultTLSParams         = {
  mode     = "client",
  protocol = "any",
  verify   = "none",
  options  = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
}

---Construct a new non-blocking connection object.
---We create the socket, set it to non-blocking, and attempt a connect.
---The real handshake is completed incrementally in `:update()`.
---@param host string e.g. "example.com"
---@param port number e.g. 443
---@param useSSL? boolean whether to wrap the connection in TLS
---@return HttpConnectionInstance|nil, string|nil errorMessage
function HttpConnectionInstance:new(host, port, useSSL)
  local sock, err = socket.tcp()
  if not sock then
    return nil, ("Failed to create TCP socket: %s"):format(tostring(err))
  end

  -- Non-blocking
  sock:settimeout(0)

  local ok, connectErr = sock:connect(host, port)
  -- Typically, non-blocking connect returns (nil, "timeout") or (nil, "Operation already in progress")
  -- if the connect is still in progress.
  -- If it's an actual error, we bail now.
  if not ok and (connectErr ~= "timeout" and connectErr ~= "Operation already in progress") then
    sock:close()
    return nil, ("Failed to connect to %s:%d: %s"):format(host, port, tostring(connectErr))
  end

  local o = {
    host          = host,
    port          = port,
    useSSL        = (useSSL == true),
    sock          = sock,
    state         = "CONNECTING",
    sendQueue     = {},
    bytesSent     = 0,
    totalReceived = 0,
    recvBuffer    = "",
    errMsg        = nil,
  }
  return setmetatable(o, self), nil
end

---Check if the connection is done (closed or error).
function HttpConnectionInstance:isClosed()
  return self.state == "CLOSED"
end

---Check if the connection handshake is done and ready for reading/writing.
function HttpConnectionInstance:isReady()
  return self.state == "READY"
end

---If state is CLOSED, this returns the error message (if any).
function HttpConnectionInstance:getError()
  return self.errMsg
end

---Close the socket right now. State becomes "CLOSED".
function HttpConnectionInstance:close(reason)
  if self.sock then
    self.sock:close()
    self.sock = nil
  end
  self.state = "CLOSED"
  self.errMsg = reason or "closed"
end

--------------------------------------------------------------------------------
-- Non-blocking handshake logic
--------------------------------------------------------------------------------

-- If we're using SSL, we wrap the existing self.sock. We do this once
-- the TCP connect is truly complete (or "already connected").
local function beginTLS(self)
  local wrapped, wrapErr = ssl.wrap(self.sock, defaultTLSParams)
  if not wrapped then
    self:close("SSL wrap failed: " .. tostring(wrapErr))
    return
  end

  -- For SNI (Server Name Indication):
  if wrapped.sni then
    pcall(wrapped.sni, wrapped, self.host)
  end

  self.sock = wrapped
  self.state = "HANDSHAKE"
  self.sock:settimeout(0) -- non-blocking mode
end

local function updateHandshake(self)
  -- dohandshake in non-blocking mode returns:
  --   true on success
  --   nil, "wantread" or "wantwrite" or "timeout" or "sslerror" on partial/in-progress
  local ok, err = self.sock:dohandshake()
  if ok == true then
    -- handshake done
    self.state = "READY"
  elseif err ~= "wantread" and err ~= "wantwrite" and err ~= "timeout" then
    -- real error
    self:close("TLS handshake failed: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- Non-blocking connect
--------------------------------------------------------------------------------

local function updateConnect(self)
  -- Trying to connect again. If it's already connected, it might say "already connected".
  local ok, err = self.sock:connect(self.host, self.port)
  if ok or (err == "already connected") then
    -- we are done connecting
    if self.useSSL then
      beginTLS(self) -- move to "HANDSHAKE"
    else
      self.state = "READY"
    end
  elseif err ~= "timeout" and err ~= "Operation already in progress" then
    -- real error
    self:close("Connect error: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- Non-blocking send
--------------------------------------------------------------------------------

---Queue some data to send asynchronously.
---@param data string
function HttpConnectionInstance:send(data)
  if self:isClosed() then return end
  if not data or #data == 0 then return end
  table.insert(self.sendQueue, data)
end

-- Attempt to send any queued data. We track partial sends.
local function flushSendQueue(self)
  while #self.sendQueue > 0 do
    local top = self.sendQueue[1]
    if #top == 0 then
      table.remove(self.sendQueue, 1)
    else
      local sent, err, partial = self.sock:send(top)
      if sent then
        -- we actually sent `sent` bytes
        self.bytesSent = self.bytesSent + sent
        if sent < #top then
          -- remove the sent part from the front
          self.sendQueue[1] = top:sub(sent + 1)
          -- we can't send more this update -> break
          break
        else
          -- entire chunk is sent
          table.remove(self.sendQueue, 1)
        end
      else
        -- no 'sent'. If err is "timeout" or "wantwrite" => partial
        if partial and partial > 0 then
          self.bytesSent = self.bytesSent + partial
          self.sendQueue[1] = top:sub(partial + 1)
        end
        if err == "timeout" or err == "wantwrite" then
          -- can't send more now
          break
        else
          -- real error => close
          self:close("Send error: " .. tostring(err))
          break
        end
      end
    end
  end
end

--------------------------------------------------------------------------------
-- Non-blocking receive
--------------------------------------------------------------------------------

---Gets newly arrived data from the socket (if any) without blocking,
---and appends it to self.recvBuffer.
local function doReceive(self)
  -- Try reading up to `pending` bytes.
  local chunk, err, partial = self.sock:receive(8192) -- 8192 is the default socket buffer size
  if chunk then
    self.totalReceived = self.totalReceived + #chunk
    self.recvBuffer = self.recvBuffer .. chunk
  elseif partial and #partial > 0 then
    self.totalReceived = self.totalReceived + #partial
    self.recvBuffer = self.recvBuffer .. partial
  end

  -- If there's a "real" error that's not just "timeout" or "wantread", close:
  if err and err ~= "timeout" and err ~= "wantread" then
    if err ~= "closed" then
      self:close("Receive error: " .. tostring(err))
    else
      -- the server closed the connection - that's not necessarily an error
      self:close("closed by peer")
    end
  end
end

--------------------------------------------------------------------------------
-- Poll/update method
--------------------------------------------------------------------------------

---Advances the connection state, attempting to connect, handshake, send, and receive data.
function HttpConnectionInstance:update()
  if self:isClosed() then
    return
  end

  -- 1) If we're still connecting, check if connect is done
  if self.state == "CONNECTING" then
    updateConnect(self)
    if self:isClosed() then return end
  end

  -- 2) If we're in TLS handshake, try continuing that
  if self.state == "HANDSHAKE" then
    updateHandshake(self)
    if self:isClosed() then return end
  end

  -- 3) If we're ready, flush any queued sends
  if self.state == "READY" then
    flushSendQueue(self)
    doReceive(self)
  end
end

--------------------------------------------------------------------------------
-- Retrieve the buffered data. You decide how to parse it.
---@return string the data accumulated so far
function HttpConnectionInstance:getData()
  return self.recvBuffer
end

---Consume some bytes from the front of the recvBuffer.
---Useful if your higher-level code parses part of the buffer
---and then discards it.
---@param numBytes number
function HttpConnectionInstance:consume(numBytes)
  if numBytes > 0 then
    self.recvBuffer = self.recvBuffer:sub(numBytes + 1)
  end
end

return HttpConnectionInstance
