--- This module fetches data from an Enphase Envoy gateway and publishes it as a Homie device.
-- (for solar systems and battery installations)
--
-- This module instantiates a homie device acting as a bridge between the Envoy local
-- API and Homie.
--
-- The module returns a single function that takes an options table. When called
-- it will construct a Homie device and add it to the Copas scheduler (without
-- running the scheduler).
-- @copyright Copyright (c) 2022-2023 Thijs Schreijer
-- @author Thijs Schreijer
-- @license MIT, see `LICENSE.md`.
-- @usage
-- local copas = require "copas"
-- local enphase = require "homie-enphase"
--
-- enphase {
--   enphase_username = "xxxxxxxx",
--   enphase_password = "xxxxxxxx",
--   enphase_serial = "xxxxxxxx",
--   enphase_hostname = "xxxxxxxx",          -- default: "envoy"
--   enphase_poll_interval = 15,             -- default: 15 seconds
--   homie_mqtt_uri = "http://mqtthost:123", -- format:  "mqtt(s)://user:pass@hostname:port"
--   homie_domain = "homie",                 -- default: "homie"
--   homie_device_id = "enphase",            -- default: "enphase-envoy"
--   homie_device_name = "M2H bridge",       -- default: "Enphase-Envoy-to-Homie bridge"
-- }
--
-- copas.loop()

local Enphase = {}
Enphase._VERSION = "0.0.1"
Enphase._COPYRIGHT = "Copyright (c) 2022-2023 Thijs Schreijer"
Enphase._DESCRIPTION = "Homie bridge for an Enphase Envoy solar installation"
Enphase.__index = Enphase

local Device = require "homie.device"
local Envoy = require "homie-enphase.envoy"
local copas = require "copas"


local function create_device(bridge, data)
  local newdevice = {
    uri = bridge.homie_mqtt_uri,
    domain = bridge.homie_domain,
    broker_state = 3,  -- recover state from broker, in 3 seconds
    id = bridge.homie_device_id,
    homie = "4.0.0",
    extensions = "",
    name = bridge.homie_device_name,
    nodes = {
      envoy = {
        name = "Envoy gateway",
        type = "solar-installation",
        properties = {
          now = {
            name = "current power in watts",
            datatype = "integer",
            settable = false,
            retained = true,
            default = data.PCU.wNow,
            unit = "W",
          },
          lifetime = {
            name = "generated energy in kWh",
            datatype = "float",
            settable = false,
            retained = true,
            default = data.PCU.whLifetime/1000,
            unit = "kWh",
          },
        },
      }
    }
  }

  return Device.new(newdevice)
end



local function timer_callback(timer, self)
  local device = self.device -- the Homie device
  local envoy = self.envoy   -- the Envoy client
  local log = self.log       -- the logger

  log:debug("[homie-enphase] starting update")

  local data, err = envoy:get_status()
  if not data then
    log:error("[homie-enphase] failed to get status update: %s", tostring(err))
    return
  end

  if not device then
    log:info("[homie-enphase] creating a new Homie device")
    device = create_device(self, data)
    self.device = device
    device:start()
  else
    log:debug("[homie-enphase] updating existing Homie device")
    device.nodes["envoy"].properties["now"]:set(data.PCU.wNow)
    device.nodes["envoy"].properties["lifetime"]:set(data.PCU.whLifetime/1000)
  end
end



return function(self)
  -- create the Envoy http client
  self.envoy = Envoy.new({
    username = self.enphase_username,
    password = self.enphase_password,
    serial = self.enphase_serial,
    hostname = self.enphase_hostname,
  })

  self.log = Envoy.log  -- the logger
  self.device = nil     -- the Homie device to create
  self.last_data = nil  -- data fetched during previous cycle

  self.timer = copas.timer.new {
    name = "homie-enphase updater",
    recurring = true,
    delay = self.enphase_poll_interval,
    initial_delay = 0,
    callback = timer_callback,
    params = self,
  }
end
