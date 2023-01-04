local package_name = "homie-envoy"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "homie-envoy"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "main" or nil,
  tag = (package_version ~= "scm") and package_version or nil,
}

description = {
  summary = "Homie bridge for an Enphase Envoy solar installation",
  detailed = [[
    Homie bridge for an Enphase Envoy solar installation
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1, < 5.5",
}

build = {
  type = "builtin",

  modules = {
    ["homie-envoy.init"] = "src/homie-envoy/init.lua",
    ["homie-envoy.enphase"] = "src/homie-envoy/enphase.lua",
  },

  install = {
    bin = {
      ["homieenvoy"] = "bin/homieenvoy.lua",
    }
  },

  copy_directories = {
    -- can be accessed by `luarocks homie-envoy doc` from the commandline
    "docs",
  },
}
