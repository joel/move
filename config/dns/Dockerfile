# The move dns image: dnsmasq answering every move-easy.docker name (and the
# apex) with the edge IP, where move-router publishes 443. Mirrors ISMS CLI V2's
# isms dns image; `bin/cli dns build` runs this (build context: config/dns/).
FROM alpine:3.22

RUN apk add --no-cache dnsmasq

COPY dnsmasq.conf /etc/dnsmasq.conf

EXPOSE 53/tcp 53/udp

# --keep-in-foreground, not --no-daemon (debug mode): with --no-daemon TCP
# queries are served in the main process, and systemd-resolved's kept-open TCP
# fallback connection then stalls docker stop's SIGTERM.
CMD ["dnsmasq", "--keep-in-foreground", "--log-facility=-", "--conf-file=/etc/dnsmasq.conf"]
