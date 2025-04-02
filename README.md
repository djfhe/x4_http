# Http client library for X4 Foundation

## This library is still work in progress

This is a simple http client library for the Game X4 Foundation.
It utilizes luasocket and luasec under the hood.
Since these libraries are synchronous, this library provides a non-blocking polling based interface to make simple http requests.

## Example usage:

#### Disclaimer:
Sending req

Sending a Get request:
```lua
  local Request = require("djfhe.http.request")

  Request.new('GET'):setUrl("https://jsonplaceholder.typicode.com/posts/1")
      :send(function(
          response, err)
        if err then
          DebugError("Error: " .. tostring(err))
        else
          local responseBodyAsTable, jsonParseError = response:getJson() -- returns a table if the response is valid json
          DebugError("Response: " .. tostring(response:getBody()))
        end
      end)
```


Sending a POST request:
```lua
  local Request = require("djfhe.http.request")

  Request.new('POST'):setUrl("https://jsonplaceholder.typicode.com/posts"):setBody({ title = "Test Post", body = "bar", userId = 10 })
      :send(function(
          response, err)
        if err then
          DebugError("Error: " .. tostring(err))
        else
          local responseBodyAsTable, jsonParseError = response:getJson() -- returns a table if the response is valid json
          DebugError("Response: " .. tostring(response:getBody()))
        end
      end)
```


You can also use luasocket and luasec directly:

```lua
  local socket = require("luasocket.socket")
  local https = require("luasec.https")
  local ltn12 = require("luasocket.ltn12")

  -- Do something with luasocket and luasec
```