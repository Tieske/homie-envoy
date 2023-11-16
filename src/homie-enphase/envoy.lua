--- This module fetches data from an Enphase Envoy gateway.
-- (for solar systems and battery installations)
--
-- info: [https://enphase.com/download/iq-gateway-access-using-local-apis-or-local-ui-token-based-authentication-tech-brief](https://enphase.com/download/iq-gateway-access-using-local-apis-or-local-ui-token-based-authentication-tech-brief)
--
-- from [this discussion](https://support.enphase.com/s/question/0D53m000095MFl3CAG/is-there-anywhere-where-i-can-view-full-local-api-documentation-for-my-envoy).
-- @copyright Copyright (c) 2022-2023 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.

local Envoy = {}
Envoy._VERSION = "0.0.1"
Envoy._COPYRIGHT = "Copyright (c) 2022-2023 Thijs Schreijer"
Envoy._DESCRIPTION = "Homie bridge for an Enphase Envoy solar installation"
Envoy.__index = Envoy

local url = require "socket.url"
local ltn12 = require "ltn12"
local json = require "cjson.safe"
local socket = require "socket"
local socket_url = require "socket.url"

-- http client to use
Envoy.http = require "ssl.https"
Envoy.log = require("logging").defaultLogger()


--- The module table containing some global settings and constants.
-- @table Enphase
--
-- @field http
-- This is a function set on the module table, such that it can
-- be overridden by another implementation (eg. Copas). The default implementation
-- uses the LuaSec one (module `ssl.https`).
--
-- @field log
-- Logger is set on the module table, to be able to override it.
-- Default is the LuaLogging default logger.


local base64_decode do
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding

  -- Decodes a base64 string.
  -- @tparam string data the base64 encoded string
  -- @treturn string the decoded string
  function base64_decode(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then
          return ''
        end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do
          r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0')
        end
        return r;
      end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then
          return ''
        end
        local c=0
        for i=1,8 do
          c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0)
        end
        return string.char(c)
      end))
  end
end


-- returns a metatable that will do an extra lookup in the array, for the first
-- entry where the value of 'keyname' matches the key we're looking for.
-- This allows to lookup in an array, by serial number for example.
local function lookup_mt(keyname)
  local mt = {
    -- if lookup fails, traverse the array for "keyName"
    __index = function(self, key)
      for _, entry in ipairs(self) do
        if type(entry) == "table" and entry[keyname] == key then
          return entry
        end
      end
      return nil
    end
  }
  return mt
end



local acquire_token do

  local redirect_status = { -- these are the redirect codes we're expecting
    [301] = true,
    [302] = true,
    [303] = true,
    [307] = true,
    [308] = true,
  }

  -- Gets a Enphase token for the specified user and serial number.
  -- @return token or nil+err
  function acquire_token(username, password, serial)

    Envoy.log:info("[Envoy] authenticating; gateway-serial: %s, user: %s", serial, username)

    -- stage 1: fetch a session id
    local done = false
    local url = "https://enlighten.enphaseenergy.com/login/login.json?"
    local ok, response_code, response_headers, response_status_line, response_body
    while not done do
      Envoy.log:debug("[Envoy] fetching session-id at: %s", url)
      local body = socket_url.escape("user[email]").."="..socket_url.escape(username).."&"
                  ..socket_url.escape("user[password]").."="..socket_url.escape(password)

      local headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Accept"] = "*/*",
        ["Content-Length"] = #body,
      }

      response_body = {}

      local r = {
        method = "POST",
        url = url,
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response_body),
      }

      ok, response_code, response_headers, response_status_line = Envoy.http.request(r)
      if not ok then
        return ok, response_code, response_headers, response_status_line
      end

      if redirect_status[response_code] then
        url = response_headers.location
        Envoy.log:debug("[Envoy] fetching session-id redirect to: %s", url)
      else
        done = true
      end
    end

    if type(response_body) == "table" then
      response_body = table.concat(response_body)
    end

    if response_code ~= 200 then
      Envoy.log:debug("[Envoy] expected 200, got %s: %s", response_code, response_body)
      return nil, "failed acquiring session_id, http status: " .. tostring(response_code)
    end

    local body_data = assert(json.decode(response_body))
    if not body_data then
      return nil, "failed acquiring session_id, invalid json: " .. tostring(response_body)
    end

    Envoy.log:debug("[Envoy] gateway-serial: %s, user: %s, got a session_id", serial, username)

    -- stage 2: fetch the token
    local body = json.encode({
      session_id = body_data.session_id,
      serial_num= serial,
      username = username,
    })

    local headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json",
      ["Content-Length"] = #body,
    }

    local response_body = {}
    local r = {
      method = "POST",
      url = "https://entrez.enphaseenergy.com/tokens",
      headers = headers,
      source = ltn12.source.string(body),
      sink = ltn12.sink.table(response_body),
    }

    local ok, response_code, response_headers, response_status_line = Envoy.http.request(r)
    if not ok then
      Envoy.log:error("[Envoy] authetication request failed with: %s", response_code)
      return ok, response_code, response_headers, response_status_line
    end

    if type(response_body) == "table" then
      response_body = table.concat(response_body)
    end

    if response_code ~= 200 then
      Envoy.log:debug("[Envoy] expected 200, got %s: %s", response_code, response_body)
      return nil, "failed acquiring token, http status: " .. tostring(response_code)
    end

    Envoy.log:debug("[Envoy] gateway-serial: %s, user: %s, got a token", serial, username)
    -- returning the full body as the token.
    return response_body
  end
end



-- Performs a HTTP request on the local Enphase API.
-- @param host (string) hostname of the Envoy gateway
-- @param path (string) the relative path within the API base path
-- @param method (string) HTTP method to use
-- @param headers (table) optional header table
-- @param query (table) optional query parameters (will be escaped)
-- @param body (table/string) optional body. If set the "Content-Length" will be
-- added to the headers. If a table, it will be send as JSON, and the
-- "Content-Type" header will be set to "application/json".
-- @return ok, response_body, response_code, response_headers, response_status_line. Response will be decded to if JSON.
local function enphase_request(host, path, method, headers, query, body)
  local response_body = {}
  headers = headers or {}

  query = query or {} do
    local r = {}
    local i = 0
    for k, v in pairs(query) do
      r[i] = "&"
      r[i+1] = url.escape(k)
      r[i+2] = "="
      r[i+3] = url.escape(v)
      i = i + 4
    end
    query = "?" .. table.concat(r)
    if query == "?" then
      query = ""
    end
  end

  if type(body) == "table" then
    body = json.encode(body)
    headers["Content-Type"] =  "application/json"
  end
  headers["Content-Length"] = #(body or "")

  local r = {
    method = assert(method, "2nd parameter 'method' missing"):upper(),
    url = "https://" .. host .. assert(path, "1st parameter 'relative-path' missing") .. query,
    headers = headers,
    source = ltn12.source.string(body or ""),
    sink = ltn12.sink.table(response_body),
  }
  Envoy.log:debug("[Envoy] making api request to: %s %s", r.method, r.url)
  -- Envoy.log:debug(r)  -- not logging because of credentials

  local ok, response_code, response_headers, response_status_line = Envoy.http.request(r)
  if not ok then
    Envoy.log:error("[Envoy] api request failed with: %s", response_code)
    return ok, response_code, response_headers, response_status_line
  end

  if type(response_body) == "table" then
    response_body = table.concat(response_body)
  end

  for name, value in pairs(response_headers) do
    if name:lower() == "content-type" and value:find("application/json", 1, true) then
      -- json body, decode
      response_body = assert(json.decode(response_body))
      break
    end
  end
  Envoy.log:debug("[Envoy] api request returned: %s", response_code)

  return response_body, response_code, response_headers, response_status_line
end



--- Creates a new Enphase object to collect data.
-- @tparam table opts table with options
-- @tparam string opts.username the username used to connect to the gateway.
-- @tparam string opts.password the password used to connect to the gateway.
-- @tparam string opts.serial the serial number of the gateway to connect to.
-- @tparam[opt="envoy"] string opts.hostname the hostname/ip where the Envoy gateway can be found.
-- @return Enphase instance
-- @usage
-- local Envoy = require "homie-enphase.envoy"
-- local myenvoy = Envoy.new {
--   username = "my.user@email.com",
--   password = "sooper_secret",
--   serial = "123456",
-- }
--
-- local data = assert(myenvoy:get_home())
function Envoy.new(opts)
  assert(type(opts) == "table", "Expected am options table")
  local self = setmetatable(opts, Envoy)

  if self.hostname == nil then self.hostname = "envoy" end
  assert(type(self.hostname) == "string", "expected opts.hostname to be a string")
  assert(type(self.username) == "string", "expected opts.username to be a string")
  assert(type(self.password) == "string", "expected opts.password to be a string")
  assert(type(self.serial) == "string", "expected opts.serial to be a string")

  Envoy.log:debug("[Envoy] new instance created for device: %s, user: %s, hostname: %s", self.serial, self.username, self.hostname)
  return self
end



--- Returns the active token, or fetches a new one if required.
-- @treturn[1] string the token.
-- @treturn[2] nil
-- @treturn[2] string error message
function Envoy:get_token()
  -- check if token has expired
  if (socket.gettime() + 60) > (self.token_expires or 0) then
    if self.token_expires then
      Envoy.log:info("[Envoy] token expired for device: %s, user: %s", self.serial, self.username)
    end
    self:clear_token()
  end

  if not self.token then
    local token, err = acquire_token(self.username, self.password, self.serial)
    if not token then
      return nil, err
    end

    local payload = token:match("%.(.*)%.")
    payload = base64_decode(payload or "")
    payload = json.decode(payload or "")
    if not payload then
      Envoy.log:error("[Envoy] received an invalid token for device: %s, user: %s", self.serial, self.username)
      return nil, "invalid token"
    end
    Envoy.log:info("[Envoy] successfully authenticated device: %s, user: %s", self.serial, self.username)
    self.token_expires = payload.exp
    self.token = token
  end

  return self.token
end



--- Clears the token, forcing a new authentication on a next request.
-- @treturn boolean true
function Envoy:clear_token()
  self.token = nil
  self.token_expires = nil
  return true
end



do
  local auth_failure_status = {
    [401] = true,
    [403] = true,
  }

  --- Makes a single GET request to the Envoy gateway based on the specified path.
  -- @tparam string path http-path to fetch (must start with a '/')
  -- @tparam[opt] table query optional query parameters (will be escaped)
  -- @treturn[1] number the http-status code of the response.
  -- @treturn[1] string|table The response body, a table if it was valid JSON.
  -- @treturn[1] table the response headers.
  -- @treturn[2] nil
  -- @treturn[2] string error message
  function Envoy:request(path, query)
    assert(path:sub(1,1) == "/", "path must start with a '/'")

    local token = self:get_token()
    local req_method = "GET"
    local req_query = query or {}
    local req_body = ""
    local req_headers = {
      Accept = "application/json",
      Authorization = "Bearer " .. token,
    }

    local body, status, headers = enphase_request(self.hostname, path, req_method, req_headers, req_query, req_body)

    if auth_failure_status[status or ""] then
      Envoy.log:error("[Envoy] received auth error: %s, clearing tokens", tostring(status))
      self:clear_token()
    end

    return status, body, headers
  end
end



--- Rewrite errors to Lua format (nil+error).
-- Takes the output of the `request` function and validates it for errors;
--
-- - nil+err
-- - mismatch in expected status code (a 200 expected, but a 404 received)
--
-- This reduces the error handling to standard Lua errors, instead of having to
-- validate each of the situations above individually.
--
-- If the status code is a 401 or 403, then the token will be cleared.
-- @tparam[opt=nil] number expected expected status code, if nil, it will be ignored
-- @tparam number status the response status code
-- @tparam string|table body the response body
-- @tparam table headers the response headers
-- @treturn[1] string|table response body
-- @treturn[1] table response headers
-- @treturn[2] nil
-- @treturn[2] string error message
-- @usage
-- local Envoy = require "enphase.envoy"
-- local envoy = Envoy.new {
--    username = "abcdef",
--    password = "xyz",
--    serial = "123",
-- }
--
-- -- Make a request where we expect a 200 result
-- local body, headers = envoy:rewrite_error(200, envoy:request("/some/thing", "GET"))
-- if not ok then
--   -- handle error
--   -- a 404 will also follow this path now, since we only want 200's
-- end
function Envoy:rewrite_error(expected, status, body, headers)
  if not status then
    return status, body
  end

  if status == 401 or status == 403 then
    -- Auth error, clear our access token
    self:clear_token()
  end

  if expected ~= nil and expected ~= status then
    if type(body) == "table" then
      body = json.encode({body = body, headers = headers})
    end
    return nil, "bad return code, expected " .. expected .. ", got "..status..". Response: "..body
  end

  return body, headers
end



--- Returns the results from `"/home.json"`.
-- @treturn[1] table response data.
-- @treturn[1] table response headers.
-- @treturn[2] nil
-- @treturn[2] string error message
function Envoy:get_home()
  return self:rewrite_error(200, self:request("/home.json"))
end



--- Returns the results from `"/production.json"`.
-- @treturn[1] table response data.
-- @treturn[1] table response headers.
-- @treturn[2] nil
-- @treturn[2] string error message
function Envoy:get_production()
  return self:rewrite_error(200, self:request("/production.json"))
end



do
  local type_mt = lookup_mt("type")
  local serial_mt = lookup_mt("serial_num")

  --- Returns the results from `"/inventory.json"`.
  -- Note that the returned body can be indexed as an array, but also by the device
  -- types (eg. `body.PCU`). The same applies for the device arrays for each type.
  -- Those can be indexed by serial number. eg. `panel = body.PCU.devices["482217048264"]`.
  --
  -- @treturn[1] table response data.
  -- @treturn[1] table response headers.
  -- @treturn[2] nil
  -- @treturn[2] string error message
  function Envoy:get_inventory()
    local body, headers = self:rewrite_error(200, self:request("/inventory.json"))
    if type(body) == "table" then
      setmetatable(body, type_mt)
      for _, dev_type in ipairs(body) do
        if type(dev_type.devices) == "table" then
          setmetatable(dev_type.devices, serial_mt)
        end
      end
    end

    return body, headers
  end
end



do
  local serial_mt = lookup_mt("serialNumber")

  --- Returns the results from `"/api/v1/production/inverters"`.
  -- Note that the returned body can be indexed as an array, but also by serial
  -- number. eg. `panel = body["482217048264"]`.
  --
  -- @treturn[1] table response data.
  -- @treturn[1] table response headers.
  -- @treturn[2] nil
  -- @treturn[2] string error message
  function Envoy:get_inverters()
    local body, headers = self:rewrite_error(200, self:request("/api/v1/production/inverters"))
    if type(body) == "table" then
      setmetatable(body, serial_mt)
    end

    return body, headers
  end
end


--- Returns combined results of `get_home` and `get_inventory`.
-- The main structure will be `get_home` with an additional key `inventory`
-- which lists all devices retrieved from `get_inventory`.
--
-- Note: the device arrays can be indexed by serial as well.
-- @treturn[1] table table with all data.
-- @treturn[2] nil
-- @treturn[2] string error message
-- @usage
-- local config = assert(envoy:get_config())
-- local first_device = config.inventory.pcu[1]
-- -- indexing by serial also works:
-- assert(first_device == config.inventory.pcu[first_device.serial_num])
function Envoy:get_config()
  local main, headers = self:get_home()
  if type(main) ~= "table" then
    if not main then
      return nil, headers
    end
    return nil, "expected json body"
  end

  local devices, headers = self:get_inventory()
  if type(devices) ~= "table" then
    if not devices then
      return nil, headers
    end
    return nil, "expected json body"
  end

  main.inventory = {}
  for _, type_list in ipairs(devices) do
    local t = type_list.type:lower() -- lowercase, same as "main.conn" table
    main.inventory[t] = type_list.devices
  end

  return main
end



--- Returns current power stats of the system. Combination of results
-- from `get_production`, `get_inventory` and `get_inverters`.
--
-- Note: the devices sub-table (array) can also be indexed by serialNumber.
-- @treturn[1] table table with all data.
-- @treturn[2] nil
-- @treturn[2] string error message
function Envoy:get_status()
  local device_tree = {}

  local inventory, headers = self:get_inventory()
  if type(inventory) ~= "table" then
    if not inventory then
      return nil, headers
    end
    return nil, "expected json body"
  end
  for _, subtype in ipairs(inventory) do
    device_tree[subtype.type] = { devices = subtype.devices }
  end

  local production, headers = self:get_production()
  if type(production) ~= "table" then
    if not production then
      return nil, headers
    end
    return nil, "expected json body"
  end
  for _, entry in pairs(production) do
    entry = entry[1] -- assume first entry, what are multiple entries???
    local key = entry.type:upper()
    if key == "INVERTERS" then -- rename "inverters" to "pcu" for consistency
      key = "PCU"
    end
    local target = device_tree[key]
    if target == nil then
      target = {}
      device_tree[key] = target
    end
    for k,v in pairs(entry) do
      target[k] = v
    end
  end

  local inverters, headers = self:get_inverters()
  if type(inverters) ~= "table" then
    if not inverters then
      return nil, headers
    end
    return nil, "expected json body"
  end
  for _, device in ipairs(device_tree.PCU.devices) do
    local inverter = inverters[device.serial_num]
    if inverter then
      for k,v in pairs(inverter) do
        device[k] = v
      end
    end
  end

  return device_tree
end



return Envoy
