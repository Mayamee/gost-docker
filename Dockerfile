# Render config.yml with credentials at build time
FROM busybox:1.37 AS config

ARG PROXY_PORT
ARG PROXY_USER
ARG PROXY_PASS

# Extended config lives in config.yml (start from config.minimal.yml)
COPY config.yml /tmp/gost.yml.template
COPY render-config.sh /tmp/render-config.sh

RUN chmod +x /tmp/render-config.sh && /tmp/render-config.sh

# Minimal final image: only the binary and baked config
FROM scratch

ARG PROXY_PORT
ARG TARGETARCH

COPY gost-linux-${TARGETARCH} /gost
COPY --from=config /config.yml /config.yml

EXPOSE ${PROXY_PORT}

CMD ["/gost", "-C", "/config.yml"]
