#!/bin/bash
set -e

echo "========================================"
echo "     INICIO SIMPLE CLÚSTER GALERA"
echo "========================================"

# COLORES
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. LIMPIAR
echo -e "${YELLOW}[1/5] Limpiando...${NC}"
docker compose down -v 2>/dev/null || true
docker network prune -f 2>/dev/null || true
sleep 2

# 2. INICIAR SOLO PXC1
echo -e "${YELLOW}[2/5] Iniciando pxc1 (bootstrap)...${NC}"
docker compose up -d pxc1

echo -e "${YELLOW}    Esperando 120 segundos (CRÍTICO)...${NC}"
for i in {1..120}; do
    echo -ne "    $i/120 segundos\r"
    sleep 1
done
echo ""

# 3. VERIFICAR PXC1
echo -e "${YELLOW}[3/5] Verificando pxc1...${NC}"
if docker exec pxc1 mysqladmin -uroot -proot ping 2>/dev/null | grep -q "mysqld is alive"; then
    echo -e "${GREEN}    ✅ pxc1 está vivo${NC}"
    
    # Mostrar IP y estado
    PXC1_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pxc1)
    echo "    IP: $PXC1_IP"
    
    echo "    Estado inicial:"
    docker exec pxc1 mysql -uroot -proot -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null || true
else
    echo -e "${RED}    ❌ pxc1 NO responde${NC}"
    echo "    Últimos logs:"
    docker logs pxc1 --tail 20
    exit 1
fi

# 4. INICIAR PXC2 Y PXC3
echo -e "${YELLOW}[4/5] Iniciando pxc2 y pxc3...${NC}"
docker compose up -d pxc2
echo "    Esperando 60 segundos para pxc2..."
sleep 60

docker compose up -d pxc3
echo "    Esperando 60 segundos para pxc3..."
sleep 60

# 5. VERIFICACIÓN FINAL
echo -e "${YELLOW}[5/5] Verificación final...${NC}"
for i in {1..10}; do
    SIZE=$(docker exec pxc1 mysql -uroot -proot -NB -e \
        "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null \
        | awk '{print $2}' 2>/dev/null || echo "0")
    
    echo "    Check $i/10 - Nodos en cluster: $SIZE"
    
    if [ "$SIZE" = "3" ]; then
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}     ✅ CLÚSTER DE 3 NODOS OPERATIVO ✅${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "Nodos:"
        docker exec pxc1 mysql -uroot -proot -e "
          SELECT 'wsrep_cluster_size' as 'Variable', VARIABLE_VALUE as 'Valor'
          FROM performance_schema.global_status 
          WHERE VARIABLE_NAME = 'wsrep_cluster_size'
          UNION
          SELECT 'wsrep_ready', VARIABLE_VALUE
          WHERE VARIABLE_NAME = 'wsrep_ready'
          UNION
          SELECT 'wsrep_incoming_addresses', VARIABLE_VALUE
          WHERE VARIABLE_NAME = 'wsrep_incoming_addresses';" 2>/dev/null || true
        
        echo ""
        echo "Conectar:"
        echo "  pxc1: mysql -h127.0.0.1 -P33061 -uroot -proot"
        echo "  pxc2: mysql -h127.0.0.1 -P33062 -uroot -proot"
        echo "  pxc3: mysql -h127.0.0.1 -P33063 -uroot -proot"
        echo "  HAProxy: mysql -h127.0.0.1 -P3307 -uroot -proot"
        echo "  Stats: http://localhost:8404/stats"
        
        exit 0
    fi
    
    sleep 10
done

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}     ⚠️  Cluster incompleto ($SIZE nodos)${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo "Diagnóstico:"
docker exec pxc1 mysql -uroot -proot -e "SHOW STATUS LIKE 'wsrep_%';" 2>/dev/null || echo "No se pudo conectar"

exit 1