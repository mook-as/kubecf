#!/usr/bin/env ruby

# This file generates the configuration for the route registrar

# This expects the following environment variables to be set:

# SYSTEM_DOMAIN: .Values.system_domain

require 'json'
require 'socket'

def secret(path)
  File.read("/run/secrets/#{path}").chomp
end

addr = Socket.getifaddrs.reject do |ifaddr|
  ifaddr.addr.nil? || (ifaddr.flags & Socket::IFF_LOOPBACK) != 0
end.select do |ifaddr|
  ifaddr.addr.ipv4?
end.first.addr.ip_address

config = {
  message_bus_servers: [{
    # XXX FIXME: This should be the pods, not the fronting service.
    host: 'nats:4222',
    user: 'nats',
    password: secret('var-nats-password/password'),
  }],
  host: "#{addr.gsub('.', '-')}.uaa-native",
  routes: [{
    health_check: {
      name: 'uaa-healthcheck',
      # XXX FIXME: do a proper check on http://:8080/healthz == 'ok'
      script_path: '/bin/true',
    },
    name: 'uaa',
    registration_interval: '10s',
    service_cert_domain_san: 'uaa.service.cf.internal',
    tags: { component: 'uaa' },
    tls_port: 8443,
    uris: [
      "uaa.#{ENV['SYSTEM_DOMAIN']}",
      "*.uaa.#{ENV['SYSTEM_DOMAIN']}",
      "login.#{ENV['SYSTEM_DOMAIN']}",
      "*.login.#{ENV['SYSTEM_DOMAIN']}",
    ]
  }],
  routing_api: {
    ca_certs: '/run/config/ca.crt',
    client_cert_path: '/run/config/client.crt',
    client_private_key_path: '/run/config/client.key',
    server_ca_cert_path: '/run/config/server_ca.crt',
    api_url: 'https://routing-api.service.cf.internal:3001',
    oauth_url: 'https://uaa.service.cf.internal:8443',
    client_id: 'routing_api_client',
    skip_ssl_validation: false,
  }
}

Dir.chdir('/run/config') do
  open('registrar_settings.json', 'w') do |f|
    f.puts config.to_json
  end
end
