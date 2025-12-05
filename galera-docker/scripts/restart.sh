#!/usr/bin/env bash
set -e

echo "==========================================="
echo "    Reiniciando clúster PXC + HAProxy"
echo "==========================================="

docker-compose down
docker-compose up -d

echo " Esperando 60s mientras el nodo 1 arranca"
sleep 60

echo "✔ Cluster reiniciado."
