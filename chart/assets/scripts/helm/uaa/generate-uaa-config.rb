#!/usr/bin/env ruby

# This script is used by the Deployment/uaa resource to generate the uaa.yaml
# configuration file.

# This expects secrets to be availble.
# This expects the following environment variables to be set:
#
# DB_ADAPTER:     Database adapter (e.g. "mysql")
# DB_URL:         Database URL
# SYSTEM_DOMAIN:  .Values.system_domain


require 'json'
require 'socket'
require 'yaml'

def secret(path)
  File.read("/run/secrets/#{path}").chomp
end

# TODO: generate the OAuth clients with some sane mechanism, rather than
# pulling it out of the BOSH configs (which should go away eventually).
manifest = YAML.load secret('with-ops/manifest.yaml')
ig = manifest['addons'].find { |g| g['name'] == 'uaa' }
job = ig['jobs'].find { |j| j['name'] == 'uaa' }

# Replace the OAuth client secrets because we don't get template-render
job['properties']['uaa']['clients'].each_value do |config|
  /^\(\((?<secret_name>[^\)]+)\)\)$/ =~ config['secret']
  next if secret_name.nil?
  secret_name.gsub! /_/, '-'
  config['secret'] = secret("var-#{secret_name}/password")
end

addr = Socket.getifaddrs.reject do |ifaddr|
  ifaddr.addr.nil? || (ifaddr.flags & Socket::IFF_LOOPBACK) != 0
end.select do |ifaddr|
  ifaddr.addr.ipv4?
end.first.addr.ip_address

config = {
  admin: {
    client_secret: secret('var-uaa-admin-client-secret/password'),
  },
  ca_certs: [ secret('var-uaa-ca/certificate') ],
  database: {
    url: ENV['DB_URL'],
    username: 'uaa',
    password: secret('var-uaa-database-password/password'),
  },
  encryption: {
    active_key_label: 'default_key',
    encryption_keys: [{
      label: 'default_key',
      passphrase: secret('var-uaa-default-encryption-passphrase/password'),
    }]
  },
  issuer: {
    uri: "https://uaa.#{ ENV['SYSTEM_DOMAIN'] }",
  },
  jwt: {
    token: {
      policy: {
        activeKeyId: 'key-1',
        keys: {
          'key-1': {
            signingKey: secret('var-uaa-jwt-signing-key/private_key'),
          },
        },
      },
    },
  },
  login: {
    entityID: "login.#{ENV['SYSTEM_DOMAIN']}",
    entityBaseURL: "https://login.#{ENV['SYSTEM_DOMAIN']}",
    saml: {
      activeKeyId: 'key-1',
      keys: {
        'key-1': {
          certificate: secret('var-uaa-login-saml/certificate'),
          key: secret('var-uaa-login-saml/private_key'),
          passphrase: '',
        }
      }
    },
    url: "https://login.#{ENV['SYSTEM_DOMAIN']}"
  },
  oauth: {
    clients: job['properties']['uaa']['clients']
  },
  scim: {
    userids_enabled: true,
    user: { override: true },
    users: []
  },
  spring_profiles: "default,#{ENV['DB_ADAPTER']}",
  uaa: {
      url: "https://uaa.#{ENV['SYSTEM_DOMAIN']}",
  },
  zones: {
    internal: {
      hostnames: [
        'uaa.service.cf.internal',
        'uaa',
        "#{addr.gsub('.', '-')}.uaa-native"
      ]
    }
  }
}

# TODO: generate the user correctly, rather than just hard-coding it
# here.
config[:scim][:users] = [{
  name: 'admin',
  password: secret('var-cf-admin-password/password'),
  firstName: '',
  lastName: '',
  email: 'admin',
  origin: 'uaa',
  groups: %w(
    clients.read
    cloud_controller.admin
    doppler.firehose
    network.admin
    openid
    routing.router_groups.read
    routing.router_groups.write
    scim.read
    scim.write
  )
}].map do |user|
  user[:groups] = user[:groups].join(',') if user[:groups].is_a? Array
  %w(name password email firstName lastName groups origin).map do |key|
    user[key.to_sym]
  end.join('|')
end

# Round trip through JSON to convert symbol (keys) to string
config = JSON.load config.to_json

Dir.chdir('/etc/config') do
  open('uaa.yml', 'w') { |f| Psych.dump(config, f) }
end
