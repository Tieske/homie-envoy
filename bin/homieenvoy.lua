#!/usr/bin/env lua

--- CLI application.
-- Description goes here.
-- @script homie-envoy
-- @usage
-- # start the application from a shell
-- homie-envoy --some --options=here

local copas = require "copas"

-- setup http-digest to use Copas async http client
local http_digest = require "http-digest"
http_digest.http = require "copas.http"

local Enphase = require "homie-envoy.enphase"

local enphase = Enphase.new { password = "xxxxxx" }

copas(function()
  local body, status, headers = enphase:get_status()
  -- print("response: ", require("pl.pretty").write({status =  status, headers = headers}))
  print("body: ", require("pl.pretty").write(body))
  -- print("indexed: ", require("pl.pretty").write(body["482217048283"]))
end)
