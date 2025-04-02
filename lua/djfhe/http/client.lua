local url                  = require("luasocket.url")
local Connection           = require("djfhe.http.connection")
local HttpResponseInstance = require("djfhe.http.response")

---@param parameters string|table<string,number|string|boolean>|nil
local function parametersToString(parameters)
    if type(parameters) == "string" then
        return parameters
    elseif type(parameters) == "table" then
        local result = {}
        for key, value in pairs(parameters) do
            if type(value) == "string" or type(value) == "number" then
                table.insert(result, key .. "=" .. tostring(value))
            end
        end
        return table.concat(result, "&")
    else
        return nil
    end
end

---@param body string|Json|nil
local function getContentTypeForBody(body)
    if type(body) == "string" then
        return "text/plain"
    elseif type(body) == "table" then
        return "application/json"
    else
        return nil
    end
end

---@alias ResponseCallback fun(response: HttpResponseInstance, error: string|nil)

---@type table<integer, { response: HttpResponseInstance, callback: ResponseCallback }>
local responsesWithCallbacks = {}
local Client = {}

---@param callback ResponseCallback
---@param response HttpResponseInstance|nil
---@param err string|nil
local function callCallback(callback, response, err)
    local ok, callbackError = pcall(callback, response, err)
    if not ok then
        DebugError("Error in callback: " .. tostring(callbackError))
    end
end

---Asynchronously send the request.
---If a callback is provided, it will be called when the response is received.
---If not, the response should be manually polled via `response:update()`.
---@param request RequestInstance
---@param callback? ResponseCallback|nil
---@return HttpResponseInstance|nil, string|nil error
function Client.send(request, callback)
    local parsedUrl = url.parse(request.url or "")
    if not parsedUrl or not parsedUrl.host then
        local errMsg = "Invalid URL: " .. tostring(request.url)

        if callback then
            callCallback(callback, nil, errMsg)
        end

        return nil, errMsg
    end

    -- Merge any request.parameters into parsedUrl.query
    local extraQuery = parametersToString(request.parameters)
    if extraQuery and #extraQuery > 0 then
        if parsedUrl.query and #parsedUrl.query > 0 then
            parsedUrl.query = parsedUrl.query .. "&" .. extraQuery
        else
            parsedUrl.query = extraQuery
        end
    end

    local host   = parsedUrl.host
    local scheme = parsedUrl.scheme or "http"
    local port   = tonumber(parsedUrl.port)
    if not port then
        port = (scheme == "https") and 443 or 80
    end

    -- Create the non-blocking connection
    local useSSL = (scheme == "https")
    local conn, err = Connection:new(host, port, useSSL)
    if not conn then
        local errMsg = "Failed to create connection: " .. tostring(err)

        if callback then
            callCallback(callback, nil, errMsg)
        end

        return nil, errMsg
    end

    -- Build the HTTP request line & headers
    local path = parsedUrl.path or "/"
    if parsedUrl.query then
        path = path .. "?" .. parsedUrl.query
    end

    local method = request.method or "GET"
    local requestLine = string.format("%s %s HTTP/1.1\r\n", method, path)

    local hdrs = request.headers or {}
    if not hdrs["Host"] then
        hdrs["Host"] = host
    end
    hdrs["Connection"] = hdrs["Connection"] or "close"

    -- Convert the body if it's a table (JSON). Otherwise assume string or empty.
    local body = ""
    if type(request.body) == "table" then
        -- If you have a JSON encoder, do it here:
        local ok, encoded = pcall(require("jsonlua.json").encode, request.body)
        body = (ok and encoded) or ""
    elseif type(request.body) == "string" then
        ---@diagnostic disable-next-line: cast-local-type
        body = request.body
    end

    -- If the method is POST or PUT and there is a body, set the headers accordingly
    if (method == "POST" or method == "PUT") and #body > 0 then
        hdrs["Content-Length"] = tostring(#body)
        hdrs["Content-Type"]   = hdrs["Content-Type"] or getContentTypeForBody(request.body)
    end

    local headerLines = {}
    for k, v in pairs(hdrs) do
        table.insert(headerLines, string.format("%s: %s", k, tostring(v)))
    end
    local headersBlob = table.concat(headerLines, "\r\n") .. "\r\n\r\n"


    -- Queue everything to send via the Connection
    conn:send(requestLine)
    conn:send(headersBlob)
    if #body > 0 then
        ---@diagnostic disable-next-line: param-type-mismatch
        conn:send(body)
    end

    -- Create and return the response object
    local response = HttpResponseInstance:new(conn)

    if callback then
        -- Store the callback for later use
        table.insert(responsesWithCallbacks, { response = response, callback = callback })
    end
    return response
end

function Client.update()
    -- Iterate through the responses and call their callbacks if available
    for i = #responsesWithCallbacks, 1, -1 do
        local item = responsesWithCallbacks[i]

        if (not item.response:isDone() and not item.response:isClosed()) then
            local err = item.response:update()

            if err then
                callCallback(item.callback, nil, err)
                table.remove(responsesWithCallbacks, i)
            end
        end

        if item.response:isDone() then
            callCallback(item.callback, item.response, nil)
            table.remove(responsesWithCallbacks, i)
        elseif item.response:isClosed() then
            callCallback(item.callback, nil, "Connection closed")
            table.remove(responsesWithCallbacks, i)
        end
    end
end

return Client
