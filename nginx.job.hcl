job "nginx" {
  datacenters = ["dc1"]

  group "nginx" {
    network {
      port "https" {
        to      = 443
        static  = 443
      }
    }

    task "server" {

      driver = "docker"

      config {
        image = "nginx"
        ports = ["https"]
        volumes = [
          "local/conf.d:/etc/nginx/conf.d",
          "local/certs:/etc/nginx/certs",
          "local/www:/home/www",
          "local/secure:/home/secure"
        ]
      }

      template {
        data = <<-EOF
        server {
          listen 443 ssl;
          server_name service-a.example.com;
          ssl_certificate "/etc/nginx/certs/server.pem";
          ssl_certificate_key "/etc/nginx/certs/server.key";

          ssl_client_certificate  "/etc/nginx/certs/server.pem"; # 클라이언트 인증서 확인을 위한 CA 인증서
          # ssl_verify_client       on; # 클라이언트 인증서 검증 활성화
          ssl_verify_client       optional;
          
          ssl_protocols           TLSv1.2 TLSv1.3;
          ssl_session_timeout     10m;
          
          proxy_read_timeout      300;
          proxy_buffers           64 16k;

          location / {
            root /home/www;
            index index.html;
          }

          location /secure {
            if ($ssl_client_verify != SUCCESS) { return 403; }
            alias /home/secure;
            index index.html;
          }
        }
        EOF

        destination   = "local/conf.d/default.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"
      }

      template {
        data = <<-EOF
        {{ with secret "pki/issue/example-dot-com" "common_name=service-a.example.com" "ttl=60m" }}
        {{ .Data.certificate }}
        {{ .Data.issuing_ca }}{{ end }}
        EOF
        destination   = "local/certs/server.pem"
      }

      template {
        data = <<-EOF
        {{ with secret "pki/issue/example-dot-com" "common_name=service-a.example.com" "ttl=60m" }}
        {{ .Data.private_key }}{{ end }}
        EOF
        destination   = "local/certs/server.key"
      }

      template {
        data = <<-EOF
        {{ with secret "pki/root/generate/internal" "common_name=example.com" "ttl=87600h" }}
        {{ .Data.certificate }}{{ end }}
        EOF
        destination   = "local/certs/ca.pem"
      }

      template {
        data = <<-EOF
        <h1>Default page</h1>
        EOF
        destination   = "local/www/index.html"
      }

      template {
        data = <<-EOF
        <h1>Secure page</h1>
        EOF
        destination   = "local/secure/index.html"
      }
    }
  }
}