# Http client library for X4 Foundation

## This library is still work in progress

This is a simple http/https client library for the Game X4 Foundation utilizing luasocket and luasec. 
Since these libraries are synchronous, this library provides a non-blocking callback based interface to make simple http requests.
Open requests will be polled every 50ms checking for new content and callback gets called as soon as the request finishes.

Protected UI needs to be disabled, since external .dll files (for luasocket and luasec) are loaded.

Guides & Doc how to compile these for X4's lua lib will follow as soon as i have some free time again.

## Example usage:
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
