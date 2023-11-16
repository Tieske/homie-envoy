FROM akorn/luarocks:lua5.1-alpine as build

RUN apk add \
    gcc \
    git \
    libc-dev \
    make \
    openssl-dev

# install dependencies separately to not have --dev versions for them as well
RUN luarocks install copas \
 && luarocks install luasec \
 && luarocks install penlight \
 && luarocks install Tieske/luamqtt --dev \
 && luarocks install homie --dev \
 && luarocks install luabitop

# copy the local repo contents and build it
COPY ./ /tmp/homie-enphase
WORKDIR /tmp/homie-enphase
RUN luarocks make

# collect cli scripts; the ones that contain "LUAROCKS_SYSCONFDIR" are Lua ones
RUN mkdir /luarocksbin \
 && grep -rl LUAROCKS_SYSCONFDIR /usr/local/bin | \
    while IFS= read -r filename; do \
      cp "$filename" /luarocksbin/; \
    done



FROM akorn/lua:5.1-alpine
RUN apk add --no-cache \
    ca-certificates \
    openssl

ENV ENPHASE_USERNAME "username..."
ENV ENPHASE_PASSWORD "password..."
ENV ENPHASE_SERIAL "serial..."
ENV ENPHASE_HOSTNAME "hostname..."
ENV ENPHASE_POLL_INTERVAL "15"
ENV HOMIE_DOMAIN "homie"
ENV HOMIE_MQTT_URI "mqtt://mqtthost:1883"
ENV HOMIE_DEVICE_ID "enphase"
ENV HOMIE_DEVICE_NAME "Enphase-Envoy-to-Homie bridge"
ENV HOMIE_LOG_LOGLEVEL "debug"

# copy luarocks tree and data over
COPY --from=build /luarocksbin/* /usr/local/bin/
COPY --from=build /usr/local/lib/lua /usr/local/lib/lua
COPY --from=build /usr/local/share/lua /usr/local/share/lua
COPY --from=build /usr/local/lib/luarocks /usr/local/lib/luarocks

CMD ["homieenphase"]
