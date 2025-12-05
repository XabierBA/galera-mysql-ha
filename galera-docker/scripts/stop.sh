#!/usr/bin/env bash
set -e

echo "==========================================="
echo "    Deteniendo clúster PXC + HAProxy"
echo "==========================================="

docker compose down

echo " Todos los contenedores detenidos."
