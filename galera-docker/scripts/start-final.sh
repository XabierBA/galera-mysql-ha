#!/bin/bash
set -e

echo "========================================"
echo "     GALERA + HAPROXY - INICIO RÁPIDO"
echo "========================================"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. LIMPIAR
echo -e "${YELLOW}[1/6] Limpiando...${NC}"
docker compose down -v 2>/dev/null || true
sleep 1

# 2. INICIAR SOLO PXC1
echo -e "${YELLOW}[2/6] Iniciando pxc1...${NC}"
docker compose up -d pxc1

echo -e "${YELLOW}    Esperando 25 segundos...${NC}"
sleep 25

# 3. VERIFICAR PXC1
echo -e "${YELLOW}[3/6] Verificando pxc1...${NC}"
if timeout 5 docker exec pxc1 mysqladmin -uroot -proot ping 2>/dev/null | grep -q "mysqld is alive"; then
    echo -e "${GREEN}    ✅ pxc1 vivo${NC}"
else
    echo -e "${YELLOW}    ⚠️  pxc1 lento, continuando...${NC}"
fi

# 4. INICIAR PXC2 Y PXC3
echo -e "${YELLOW}[4/6] Iniciando pxc2 y pxc3...${NC}"
docker compose up -d pxc2 pxc3

echo -e "${YELLOW}    Esperando 20 segundos...${NC}"
sleep 20

# 5. INICIAR HAPROXY
echo -e "${YELLOW}[5/6] Iniciando HAProxy...${NC}"
docker compose up -d haproxy

sleep 5

# 6. VERIFICACIÓN RÁPIDA
echo -e "${YELLOW}[6/6] Verificación final...${NC}"

# Verificar cluster
if docker exec pxc1 mysql -uroot -proot -e "SELECT 1;" 2>/dev/null > /dev/null; then
    SIZE=$(docker exec pxc1 mysql -uroot -proot -NB -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}' 2>/dev/null || echo "0")
    
    echo -n "    Cluster: "
    if [ "$SIZE" = "3" ]; then
        echo -e "${GREEN}✅ $SIZE nodos${NC}"
    else
        echo -e "${YELLOW}⚠️  $SIZE nodos${NC}"
    fi
fi

# Verificar HAProxy
if curl -s http://localhost:8404/stats > /dev/null; then
    echo -e "    HAProxy: ${GREEN}✅ Estadísticas disponibles${NC}"
else
    echo -e "    HAProxy: ${YELLOW}⚠️  Estadísticas no disponibles${NC}"
fi

echo ""
echo "🎯 LISTO PARA USAR:"
echo "  MySQL directo:"
echo "    pxc1: mysql -h127.0.0.1 -P33061 -uroot -proot"
echo "    pxc2: mysql -h127.0.0.1 -P33062 -uroot -proot"
echo "    pxc3: mysql -h127.0.0.1 -P33063 -uroot -proot"
echo ""
echo "  MySQL balanceado (HAProxy):"
echo "    mysql -h127.0.0.1 -P3307 -uroot -proot"
echo ""
echo "  Estadísticas HAProxy:"
echo "    http://localhost:8404/stats"
echo ""
echo "  Comandos útiles:"
echo "    Estado cluster: docker exec pxc1 mysql -uroot -proot -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\""
echo "    Ver logs: docker compose logs -f pxc1"