#!/usr/bin/env bash

export ENPHASE_USERNAME="user@email.com"
export ENPHASE_PASSWORD="soopersecret"
export ENPHASE_SERIAL="device serial number here..."
export ENPHASE_HOSTNAME="envoy"
export ENPHASE_POLL_INTERVAL=15
export HOMIE_DOMAIN="homie"
export HOMIE_MQTT_URI="mqtt://synology"
export HOMIE_DEVICE_ID="enphase-envoy"
export HOMIE_DEVICE_NAME="Enphase-Envoy-to-Homie bridge"

# export HOMIE_LOG_LOGGER="rsyslog"
export HOMIE_LOG_LOGLEVEL="info"
# export HOMIE_LOG_LOGPATTERN="%message (%source)"
# export HOMIE_LOG_RFC="rfc5424"
# export HOMIE_LOG_MAXSIZE="8000"
# export HOMIE_LOG_HOSTNAME="synology.local"
# export HOMIE_LOG_PORT="8514"
# export HOMIE_LOG_PROTOCOL="tcp"
# export HOMIE_LOG_IDENT="homiemillheat"


LUA_PATH="./src/?/init.lua;./src/?.lua;$LUA_PATH"
lua bin/homieenphase.lua

# docker run -it --rm \
#     -e ENPHASE_USERNAME \
#     -e ENPHASE_PASSWORD \
#     -e ENPHASE_SERIAL \
#     -e ENPHASE_HOSTNAME \
#     -e ENPHASE_POLL_INTERVAL \
#     -e HOMIE_DOMAIN \
#     -e HOMIE_MQTT_URI \
#     -e HOMIE_DEVICE_ID \
#     -e HOMIE_DEVICE_NAME \
#     -e HOMIE_LOG_LOGGER \
#     -e HOMIE_LOG_LOGLEVEL \
#     -e HOMIE_LOG_LOGPATTERN \
#     -e HOMIE_LOG_RFC \
#     -e HOMIE_LOG_MAXSIZE \
#     -e HOMIE_LOG_HOSTNAME \
#     -e HOMIE_LOG_PORT \
#     -e HOMIE_LOG_PROTOCOL \
#     -e HOMIE_LOG_IDENT \
#     tieske/homie-enphase:dev
