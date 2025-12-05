#!/usr/bin/env bash
set -e

echo "======================================================"
echo "    ELIMINANDO COMPLETAMENTE EL CLÚSTER Y DATOS"
echo "======================================================"

docker-compose down -v

echo "✔ Se eliminaron contenedores, volúmenes y redes."
echo "✔ El sistema quedó totalmente limpio."
