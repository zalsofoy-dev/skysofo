{
  "log": {
    "loglevel": "warning",
    "access": ""
  },
  "inbounds": [
    {
      "port": __PORT__,
      "listen": "0.0.0.0",
      "protocol": "__PROTO__",
      "settings": {
        "clients": [
          {
            "id": "__USER_ID__"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "__NETWORK__",
        "security": "tls",
        "tlsSettings": {
          "minVersion": "1.2",
          "cipherSuites": [
            "TLS_AES_256_GCM_SHA384",
            "TLS_CHACHA20_POLY1305_SHA256",
            "TLS_AES_128_GCM_SHA256"
          ],
          "alpn": ["h2", "http/1.1"],
          "preferServerCipherSuites": true,
          "sessionTicket": true
        },
        "wsSettings": {
          "path": "__WS_PATH__",
          "host": "__WS_HOST__",
          "headers": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
          },
          "acceptProxyProtocol": false
        }
      },
      "sniffing": {
        "enabled": false
      }
    },
    {
      "port": 10085,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "streamSettings": {
        "sockopt": {
          "tcpFastOpen": true,
          "tfo": 1,
          "mark": 255,
          "dialerProxy": ""
        }
      },
      "tag": "direct"
    },
    {
      "protocol": "freedom",
      "tag": "api"
    }
  ],
  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      }
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": false,
        "statsUserDownlink": false,
        "bufferSize": 32768,
        "uplinkCapacity": __SPEED_LIMIT__,
        "downlinkCapacity": __SPEED_LIMIT__
      }
    },
    "system": {
      "statsInboundUplink": false,
      "statsInboundDownlink": false
    }
  }
}
