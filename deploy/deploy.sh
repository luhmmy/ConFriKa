#!/usr/bin/env bash
# ==============================================================================
# ConFriKa — Docker Compose deployment (PostgreSQL 16, Redis 7, FastAPI + NLLB,
# Nginx, Coturn). Secrets are read from deploy/.env.
# ==============================================================================
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"

echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}   ConFriKa — Docker Compose Deployment${NC}"
echo -e "${CYAN}============================================================${NC}"

echo -e "\n${YELLOW}[1/5] Checking prerequisites...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}docker is required.${NC}"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo -e "${RED}docker compose v2 is required.${NC}"; exit 1; }

if [ ! -f "$DEPLOY_DIR/.env" ]; then
    echo -e "${RED}Missing deploy/.env. Create it with strong secrets:${NC}"
    echo '  SECRET_KEY=... POSTGRES_PASSWORD=... REDIS_PASSWORD=... TURN_SECRET=...'
    exit 1
fi
echo -e "${GREEN}OK.${NC}"

echo -e "\n${YELLOW}[2/5] Building backend image (installs torch + NLLB deps)...${NC}"
docker compose build backend

echo -e "\n${YELLOW}[3/5] Starting PostgreSQL + Redis...${NC}"
docker compose up -d postgres redis
printf "Waiting for Postgres"
until [ "$(docker inspect -f '{{.State.Health.Status}}' confrika_postgres 2>/dev/null)" = "healthy" ]; do printf "."; sleep 2; done
printf "\nWaiting for Redis"
until [ "$(docker inspect -f '{{.State.Health.Status}}' confrika_redis 2>/dev/null)" = "healthy" ]; do printf "."; sleep 2; done
echo -e "\n${GREEN}Data stores healthy.${NC}"

echo -e "\n${YELLOW}[4/5] Starting backend, nginx, coturn...${NC}"
docker compose up -d backend nginx coturn

echo -e "\n${YELLOW}[5/5] Verifying API health...${NC}"
sleep 5
for i in $(seq 1 30); do
    if curl -fs http://localhost:8000/health >/dev/null 2>&1; then
        echo -e "${GREEN}Backend API is healthy.${NC}"
        curl -s http://localhost:8000/health
        break
    fi
    sleep 2
done

echo -e "\n${CYAN}============================================================${NC}"
echo -e "${GREEN}Deployed.${NC}"
echo -e "   API:        http://localhost:8000"
echo -e "   API docs:   http://localhost:8000/docs"
echo -e "   Via nginx:  http://localhost/"
echo -e "   Chat WS:    ws://localhost:8000/ws/chat?token=JWT"
echo -e "   Calls WS:   ws://localhost:8000/ws/calls?token=JWT"
echo -e "${YELLOW}Note: the NLLB model (~2.4GB) downloads on first run into the"
echo -e "model_cache volume; /health shows translation_model_loaded=true when ready.${NC}"
echo -e "${CYAN}============================================================${NC}"
