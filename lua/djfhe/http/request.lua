local httpClient = require("djfhe.http.client")

---@alias RequestMethod
---| '"GET"'
---| '"POST"'
---| '"PUT"'
---| '"DELETE"'

---@alias Parameter string|number|integer|boolean
---@alias Json table<string|integer,Parameter>|nil

-- Returns the given method if valid or returns 'GET'
---@param method any
---@return RequestMethod
local function validateMethod(method)
  if type(method) ~= "string" then
    return "GET" -- Default method
  end

  local validMethods = { GET = true, POST = true, PUT = true, DELETE = true }
  if validMethods[method] then
    return method
  else
    return "GET" -- Default method
  end
end

---@class (exact) RequestInstance
---@field method RequestMethod
---@field url string
---@field headers table<string,Parameter>
---@field parameters table<string,Parameter>|string|nil
---@field body string|Json|nil
---@field setMethod fun(self: RequestInstance, method: RequestMethod): RequestInstance
---@field addHeader fun(self: RequestInstance, key: string, value: Parameter): RequestInstance
---@field setHeaders fun(self: RequestInstance, headers: table<string,Parameter>): RequestInstance
---@field setUrl fun(self: RequestInstance, url: string): RequestInstance
---@field addParameter fun(self: RequestInstance, key: string, parameter: Parameter): RequestInstance
---@field setParameters fun(self: RequestInstance, parameters: table<string,Parameter>): RequestInstance
---@field setBody fun(self: RequestInstance, body: string|Json): RequestInstance
---@field send fun(self: RequestInstance, callback?: ResponseCallback|nil): HttpResponseInstance|nil, string|nil error
local RequestInstance = {}
---@diagnostic disable-next-line: inject-field
RequestInstance.__index = RequestInstance

--- @param self RequestInstance
--- @param method RequestMethod
--- @return RequestInstance
function RequestInstance:setMethod(method)
  self.method = validateMethod(method)
  return self
end

--- @param self RequestInstance
--- @param key string
--- @param value Parameter
--- @return RequestInstance
function RequestInstance:addHeader(key, value)
  self.headers[key] = value
  return self
end

--- @param self RequestInstance
--- @param headers table<string,Parameter>
--- @return RequestInstance
function RequestInstance:setHeaders(headers)
  self.headers = {}

  for key, value in pairs(headers) do
    self.headers[key] = value
    return self
  end
end

--- @param self RequestInstance
--- @param url string
--- @return RequestInstance
function RequestInstance:setUrl(url)
  self.url = url
  return self
end

--- @param self RequestInstance
--- @param key string
--- @param parameter Parameter
--- @return RequestInstance
function RequestInstance:addParameter(key, parameter)
  if type(self.parameters) ~= "table" then
    self.parameters = {}
  end
  self.parameters[key] = parameter
  return self
end

--- @param self RequestInstance
--- @param parameters table<string,Parameter>
--- @return RequestInstance
function RequestInstance:setParameters(parameters)
  self.parameters = {}

  for key, value in pairs(parameters) do
    self.parameters[key] = value
  end

  return self
end

--- @param self RequestInstance
--- @param body string|Json
--- @return RequestInstance
function RequestInstance:setBody(body)
  self.body = body
  return self
end

--- @param self RequestInstance
--- @param callback? ResponseCallback|nil
--- @return HttpResponseInstance|nil, string|nil error
function RequestInstance:send(callback)
  return httpClient.send(self, callback)
end

---@class (exact) Request
---@field new fun(method?: RequestMethod|nil, headers?: table<string,Parameter>|nil, url?: string|nil, parameters?: table<string,Parameter>|string|nil, body?: string|Json|nil): RequestInstance
local Request = {}
---@diagnostic disable-next-line: inject-field
Request.__index = Request

function Request.new(method, headers, url, parameters, body)
  local instance = {
    method     = validateMethod(method),
    headers    = headers or {},
    url        = url or "",
    parameters = parameters or nil,
    body       = body or nil,
  }

  return setmetatable(instance, RequestInstance)
end

return Request
