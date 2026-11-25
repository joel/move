#!/usr/bin/env ruby

require "yaml"
require "fileutils"
require_relative "../edge/edge"
require_relative "certificate_store"
require_relative "router_config"

module AppCLI
  module Services
    # move-router's entry for one served worktree app: its own file in the
    # file provider's directory, `dynamic/wt-<wt>.yml`, plus its own TLS leaf.
    # Traefik watches the directory, so writing the file adds the route and
    # deleting it removes the route, without a router restart. RouterConfig
    # keeps owning main's `routes.yml`.
    #
    # One router covers the worktree apex (move.<zone>) and every org host
    # (<slug>.<zone>): a single label left of the worktree zone, which is also
    # exactly what the zone leaf's wildcard covers. Main's catch-all matches
    # one label left of move-easy.docker only, so the two never overlap.
    class WorktreeRoute
      CERTS_MOUNT = "/certs".freeze

      # @param app [WorktreeApp]
      def initialize(app:, dir: Edge::ROUTER_DIR, certs: CertificateStore.new)
        @app = app
        @dir = dir
        @certs = certs
      end

      def path = File.join(dir, "dynamic", "wt-#{app.label}.yml")

      def write!
        certs.ensure!
        certs.ensure_zone_leaf!(app.zone)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp"
        File.write(tmp, RouterConfig::HEADER + YAML.dump(config))
        File.rename(tmp, path)
      end

      def remove!
        FileUtils.rm_f(path)
        certs.remove_zone_leaf(app.zone)
      end

      def config
        name = "wt-#{app.label}"
        {
          "http" => {
            "routers" => {
              name => { "rule" => rule, "entryPoints" => ["websecure"], "service" => name, "tls" => {} }
            },
            "services" => {
              name => { "loadBalancer" => { "servers" => [{ "url" => "http://#{app.container}:9292" }] } }
            }
          },
          "tls" => { "certificates" => [{ "certFile" => mounted(certs.zone_cert_path(app.zone)),
                                          "keyFile" => mounted(certs.zone_key_path(app.zone)) }] }
        }
      end

      def rule = "HostRegexp(`^[a-z0-9-]+\\.#{app.zone.gsub(".", "\\.")}$`)"

      private

      attr_reader :app, :dir, :certs

      # The router mounts the leaf directory at /certs.
      def mounted(host_path) = File.join(CERTS_MOUNT, File.basename(host_path))
    end
  end
end
