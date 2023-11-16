#!/usr/bin/env lua

--- Main CLI application.
-- Reads configuration from environment variables and starts the Enphase-to-Homie bridge.
-- Does not support any CLI parameters.
--
-- For configuring the log, use LuaLogging environment variable prefix `"HOMIE_LOG_"`, see
-- "logLevel" in the example below.
-- @script homieenphase
-- @usage
-- # configure parameters as environment variables
-- export ENPHASE_USERNAME="xxxxxxxx"
-- export ENPHASE_PASSWORD="xxxxxxxx"
-- export ENPHASE_SERIAL="xxxxxxxx"
-- export ENPHASE_HOSTNAME="xxxxxxxx"         # default: "envoy"
-- export ENPHASE_POLL_INTERVAL=5             # default: 15 seconds
-- export HOMIE_MQTT_URI="mqtt://synology"    # format:  "mqtt(s)://user:pass@hostname:port"
-- export HOMIE_DOMAIN="homie"                # default: "homie"
-- export HOMIE_DEVICE_ID="enphase"           # default: "enphase-envoy"
-- export HOMIE_DEVICE_NAME="EE2H bridge"     # default: "Enphase-Envoy-to-Homie bridge"
-- export HOMIE_LOG_LOGLEVEL="info"           # default: "INFO"
--
-- # start the application
-- homieenphase


local ll = require "logging"
local copas = require "copas"
require("logging.rsyslog").copas() -- ensure copas, if rsyslog is used
local logger = assert(require("logging.envconfig").set_default_logger("HOMIE_LOG"))


-- setup Envoy client to use proper http and log clients
local Envoy = require("homie-enphase.envoy")
Envoy.http = copas.http
Envoy.log = logger


do -- set Copas errorhandler
  local lines = require("pl.stringx").lines

  copas.setErrorHandler(function(msg, co, skt)
    msg = copas.gettraceback(msg, co, skt)
    for line in lines(msg) do
      ll.defaultLogger():error(line)
    end
  end, true)
end


print("starting Enphase-Envoy-to-Homie bridge")
logger:info("starting Enphase-Envoy-to-Homie bridge")


local opts = {
  enphase_username = assert(os.getenv("ENPHASE_USERNAME"), "environment variable ENPHASE_USERNAME not set"),
  enphase_password = assert(os.getenv("ENPHASE_PASSWORD"), "environment variable ENPHASE_PASSWORD not set"),
  enphase_serial = assert(os.getenv("ENPHASE_SERIAL"), "environment variable ENPHASE_SERIAL not set"),
  enphase_hostname = os.getenv("ENPHASE_HOSTNAME") or "envoy",
  enphase_poll_interval = tonumber(os.getenv("ENPHASE_POLL_INTERVAL")) or 15,
  homie_domain = os.getenv("HOMIE_DOMAIN") or "homie",
  homie_mqtt_uri = assert(os.getenv("HOMIE_MQTT_URI"), "environment variable HOMIE_MQTT_URI not set"),
  homie_device_id = os.getenv("HOMIE_DEVICE_ID") or "enphase-envoy",
  homie_device_name = os.getenv("HOMIE_DEVICE_NAME") or "Enphase-Envoy-to-Homie bridge",
}

logger:info("Bridge configuration:")
logger:info("ENPHASE_USERNAME: %s", opts.enphase_username)
logger:info("ENPHASE_PASSWORD: ********")
logger:info("ENPHASE_SERIAL: %s", opts.enphase_serial)
logger:info("ENPHASE_HOSTNAME: %s", opts.enphase_hostname)
logger:info("ENPHASE_POLL_INTERVAL: %d seconds", opts.enphase_poll_interval)
logger:info("HOMIE_DOMAIN: %s", opts.homie_domain)
logger:info("HOMIE_MQTT_URI: %s", opts.homie_mqtt_uri)
logger:info("HOMIE_DEVICE_ID: %s", opts.homie_device_id)
logger:info("HOMIE_DEVICE_NAME: %s", opts.homie_device_name)


copas.loop(function()
  require("homie-enphase")(opts)
end)

ll.defaultLogger():info("Enphase-Envoy-to-Homie bridge exited")
