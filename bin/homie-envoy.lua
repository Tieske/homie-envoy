#!/usr/bin/env lua

--- CLI application.
-- Description goes here.
-- @script homie-envoy
-- @usage
-- # start the application from a shell
-- homie-envoy --some --options=here

print("Welcome to the homie-envoy CLI, echoing arguments:")
for i, val in ipairs(arg) do
  print(i .. ":", val)
end
