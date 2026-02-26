#!/bin/bash
set -e

echo "=== Priority Lists — Supabase VPS Setup ==="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "Docker installed."
else
    echo "Docker already installed."
fi

# Check Docker Compose
if ! docker compose version &> /dev/null; then
    echo "ERROR: docker compose not available. Update Docker or install the compose plugin."
    exit 1
fi

echo ""

# Create project directory
mkdir -p /opt/priority-lists/supabase
cd /opt/priority-lists/supabase

# Generate secrets
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | head -c 40)
JWT_SECRET=$(openssl rand -base64 48 | tr -d '/+=' | head -c 64)

echo "Generated POSTGRES_PASSWORD and JWT_SECRET."
echo ""

# Generate ANON_KEY (JWT with role=anon, exp=2099)
ANON_KEY=$(docker run --rm ghcr.io/supabase/gotrue:v2.170.0 sh -c \
  "echo '{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$(date +%s),\"exp\":4102444800}' | \
   python3 -c \"
import sys, json, hmac, hashlib, base64
header = base64.urlsafe_b64encode(json.dumps({'alg':'HS256','typ':'JWT'}).encode()).rstrip(b'=').decode()
payload = base64.urlsafe_b64encode(sys.stdin.read().encode()).rstrip(b'=').decode()
sig = base64.urlsafe_b64encode(hmac.new(b'${JWT_SECRET}', (header+'.'+payload).encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
print(header+'.'+payload+'.'+sig)
\"" 2>/dev/null) || true

# If Docker method failed, generate with openssl
if [ -z "$ANON_KEY" ]; then
    echo "Generating JWT keys with openssl..."
    generate_jwt() {
        local role=$1
        local header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
        local payload=$(echo -n "{\"role\":\"${role}\",\"iss\":\"supabase\",\"iat\":$(date +%s),\"exp\":4102444800}" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
        local signature=$(echo -n "${header}.${payload}" | openssl dgst -sha256 -hmac "${JWT_SECRET}" -binary | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
        echo "${header}.${payload}.${signature}"
    }
    ANON_KEY=$(generate_jwt "anon")
    SERVICE_ROLE_KEY=$(generate_jwt "service_role")
else
    # Generate SERVICE_ROLE_KEY same way
    SERVICE_ROLE_KEY=$(docker run --rm ghcr.io/supabase/gotrue:v2.170.0 sh -c \
      "echo '{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$(date +%s),\"exp\":4102444800}' | \
       python3 -c \"
import sys, json, hmac, hashlib, base64
header = base64.urlsafe_b64encode(json.dumps({'alg':'HS256','typ':'JWT'}).encode()).rstrip(b'=').decode()
payload = base64.urlsafe_b64encode(sys.stdin.read().encode()).rstrip(b'=').decode()
sig = base64.urlsafe_b64encode(hmac.new(b'${JWT_SECRET}', (header+'.'+payload).encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
print(header+'.'+payload+'.'+sig)
\"" 2>/dev/null)
fi

# Detect server IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")

# Write .env
cat > .env << EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}

API_EXTERNAL_URL=http://${SERVER_IP}:8000
SITE_URL=http://${SERVER_IP}:8000

STUDIO_DEFAULT_ORGANIZATION=Priority Lists
STUDIO_DEFAULT_PROJECT=Priority Lists
STUDIO_PORT=3000

POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432
EOF

echo ""
echo "=== .env created ==="
echo ""
echo "==========================================="
echo "  Save these for GitHub Secrets:"
echo "==========================================="
echo ""
echo "  SUPABASE_URL=http://${SERVER_IP}:8000"
echo "  SUPABASE_ANON_KEY=${ANON_KEY}"
echo ""
echo "==========================================="
echo ""
echo "To start Supabase, copy docker-compose.yml and volumes/ here, then run:"
echo "  cd /opt/priority-lists/supabase"
echo "  docker compose up -d"
echo ""
echo "Studio will be at: http://${SERVER_IP}:3000"
echo "API will be at:    http://${SERVER_IP}:8000"
