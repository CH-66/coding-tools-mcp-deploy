apisix:
  node_listen:
    - ip: 127.0.0.1
      port: __APISIX_GATEWAY_PORT__
  enable_ipv6: false
  enable_control: false
  enable_server_tokens: false

deployment:
  role: traditional
  role_traditional:
    config_provider: etcd
  admin:
    allow_admin:
      - 127.0.0.0/24
    admin_key:
      - name: admin
        key: __APISIX_ADMIN_KEY__
        role: admin
    admin_listen:
      ip: 127.0.0.1
      port: __APISIX_ADMIN_PORT__
  etcd:
    host:
      - "http://127.0.0.1:__ETCD_CLIENT_PORT__"
    prefix: "/coding-tools-mcp/apisix"
    timeout: 30
