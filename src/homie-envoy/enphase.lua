--- This module fetcheds data from an Enphase Envoy gateway.
-- (for solar systems and battery installations)
--
-- @copyright Copyright (c) 2022-2023 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.

local Enphase = {}
Enphase._VERSION = "0.0.1"
Enphase._COPYRIGHT = "Copyright (c) 2022-2023 Thijs Schreijer"
Enphase._DESCRIPTION = "Homie bridge for an Enphase Envoy solar installation"
Enphase.__index = Enphase

local digest = require "http-digest"
local json = require "cjson.safe"



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


--- Creates a new Enphase object to collect data.
-- @tparam table opts table with options
-- @tparam[opt="envoy"] string opts.hostname the hostname/ip where the Envoy gateway can be found.
-- @tparam[opt="envoy"] string opts.username the username used to connect to the gateway.
-- @tparam string opts.password the password used to connect to the gateway.
-- @return Enphase instance
function Enphase.new(opts)
  assert(type(opts) == "table", "Expected am options table")
  local self = setmetatable(opts, Enphase)

  if self.hostname == nil then self.hostname = "envoy" end
  assert(type(self.hostname) == "string", "expected opts.hostname to be a string")

  if self.username == nil then self.username = "envoy" end
  assert(type(self.username) == "string", "expected opts.username to be a string")
  assert(type(self.password) == "string", "expected opts.password to be a string")

  self.baseurl = ("http://%s:%s@%s"):format(self.username, self.password, self.hostname)

  return self
end


--- Makes a single reuqest to the Envoy gateway base on the specified path.
-- @tparam string path http-path to fetch (must start with a '/')
-- @treturn[1] string|table The response body, a table if it was valid JSON.
-- @treturn[1] number the http-status code of the response.
-- @treturn[1] table the response headers.
-- @treturn[2] nil
-- @treturn[2] string error message
function Enphase:request(path)
  assert(path:sub(1,1) == "/", "path must start with a '/'")

  local body, status, headers = digest.request(self.baseurl .. path)
  if not body then
    return nil, status
  end

  local decoded = json.decode(body)
  if decoded then -- succesfully decoded json, so replace body with table
    body = decoded
  end

  return body, status, headers
end


--- Returns the results from "/home.json".
-- see `Enphase:request` for return values.
function Enphase:get_home()
  return self:request("/home.json")
end



--- Returns the results from "/production.json".
-- see `Enphase:request` for return values.
function Enphase:get_production()
  return self:request("/production.json")
end



do
  local type_mt = lookup_mt("type")
  local serial_mt = lookup_mt("serial_num")

  --- Returns the results from "/inventory.json".
  -- Note that the returned body can be indexed as an array, but also by the device
  -- types (eg. `body.PCU`). The same applies for the device arrays for each type.
  -- Those can be indexed by serial number. eg. `panel = body.PCU.devices["482217048264"]`.
  --
  -- See `Enphase:request` for return values.
  function Enphase:get_inventory()
    local body, status, headers = self:request("/inventory.json")
    if type(body) == "table" then
      setmetatable(body, type_mt)
      for _, dev_type in ipairs(body) do
        if type(dev_type.devices) == "table" then
          setmetatable(dev_type.devices, serial_mt)
        end
      end
    end

    return body, status, headers
  end
end



do
  local serial_mt = lookup_mt("serialNumber")

  --- Returns the results from "/api/v1/production/inverters".
  -- Note that the returned body can be indexed as an array, but also by serial
  -- number. eg. `panel = body["482217048264"]`.
  --
  -- See `Enphase:request` for return values.
  function Enphase:get_inverters()
    local body, status, headers = self:request("/api/v1/production/inverters")
    if type(body) == "table" then
      setmetatable(body, serial_mt)
    end

    return body, status, headers
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
-- local config = assert(enphase:get_config())
-- local first_device = config.inventory.pcu[1]
-- -- indexing by serial also works:
-- assert(first_device == config.inventory.pcu[first_device.serial_num])
function Enphase:get_config()
  local main, status, _ = self:get_home()
  if type(main) ~= "table" then
    return nil, tostring(main)..": "..tostring(status)
  end

  local devices, status, _ = self:get_inventory()
  if type(devices) ~= "table" then
    return nil, tostring(devices)..": "..tostring(status)
  end

  main.inventory = {}
  for _, type_list in ipairs(devices) do
    local t = type_list.type:lower() -- lowercase, same as "main.conn" table
    main.inventory[t] = type_list.devices
  end

  return main
end



--- Returns current power stats of the system. Combination of results
-- from `get_production` and `get_inverters.
--
-- Note: the devices sub-table (array) can also be indexed by serialNumber.
-- @treturn[1] table table with all data.
-- @treturn[2] nil
-- @treturn[2] string error message
function Enphase:get_status()
  local production, status, _ = self:get_production()
  if type(production) ~= "table" then
    return nil, tostring(production)..": "..tostring(status)
  end

  local inverters, status, _ = self:get_inverters()
  if type(inverters) ~= "table" then
    return nil, tostring(inverters)..": "..tostring(status)
  end

  local results = {}
  for _, entry in pairs(production) do
    entry = entry[1] -- assume first entry, what are multiple entries???
    local key = entry.type
    if key == "inverters" then -- rename "inverters" to "pcu" for consistency
      key = "pcu"
    end
    results[key] = entry
    entry.devices = entry.devices or {}
  end

  results.pcu.devices = inverters

  return results
end

return Enphase
