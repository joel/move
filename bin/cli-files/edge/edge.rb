#!/usr/bin/env ruby

require_relative "../services/helpers"

module AppCLI
  module Services
    # Shared constants for Move's local HTTPS edge (move-dns + move-router),
    # the ISMS CLI V2 pattern. Everything lives on its own loopback IP so it
    # runs side by side with the ISMS stack, which owns 127.0.0.1:53/443.
    module Edge
      IP = ENV.fetch("MOVE_EDGE_IP", "127.0.0.2").freeze
      DOMAIN = DEV_DOMAIN
      STATE_DIR = File.join(
        ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local/state")), APP_NAME
      ).freeze
      ROUTER_DIR = File.join(STATE_DIR, "router").freeze
      CERTS_DIR = File.join(STATE_DIR, "certs").freeze
      # Leaf material only — the directory the router mounts. The CA key stays
      # outside it and never enters a container.
      LEAF_DIR = File.join(CERTS_DIR, "leaf").freeze
      DELEGATE_PATH = "/etc/systemd/dns-delegate.d/move-easy-docker.dns-delegate".freeze
    end
  end
end
