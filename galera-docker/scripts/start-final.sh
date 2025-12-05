#!/bin/bash
set -e

echo "========================================"
echo "     INICIO DEFINITIVO CLUSTER GALERA"
echo "========================================"

# COLORES
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. LIMPIAR TODO
echo -e "${YELLOW}[1/7] Limpiando TODO...${NC}"
docker compose down -v 2>/dev/null || true
docker network rm galera-net 2>/dev/null || true
sleep 3

# 2. CREAR RED
echo -e "${YELLOW}[2/7] Creando red...${NC}"
docker network create --driver bridge --subnet 10.99.88.0/24 galera-net 2>/dev/null || true

# 3. INICIAR SOLO PXC1
echo -e "${YELLOW}[3/7] Iniciando SOLO pxc1...${NC}"
docker compose up -d pxc1

echo -e "${YELLOW}    ESPERA CRÍTICA: 45 segundos...${NC}"
for i in {1..45}; do
    echo -ne "    $i/45 segundos\r"
    sleep 1
done
echo ""

# 4. VERIFICAR PXC1
echo -e "${YELLOW}[4/7] Verificando pxc1...${NC}"
if docker exec pxc1 mysqladmin -uroot -proot ping 2>/dev/null | grep -q "mysqld is alive"; then
    echo -e "${GREEN}    ✅ pxc1 vivo${NC}"
    
    # Forzar configuración Galera
    echo "    Configurando wsrep_cluster_address en pxc1..."
    docker exec pxc1 mysql -uroot -proot -e \
      "SET GLOBAL wsrep_cluster_address='gcomm://10.99.88.10,10.99.88.11,10.99.88.12';" 2>/dev/null || true
    
    # Mostrar estado
    docker exec pxc1 mysql -uroot -proot -e \
      "SHOW VARIABLES LIKE 'wsrep_cluster_address'; SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null || true
else
    echo -e "${RED}    ❌ pxc1 muerto${NC}"
    docker logs pxc1 --tail 30
    exit 1
fi

# 5. INICIAR PXC2
echo -e "${YELLOW}[5/7] Iniciando pxc2...${NC}"
docker compose up -d pxc2

echo -e "${YELLOW}    Esperando 30 segundos...${NC}"
sleep 30

# Verificar que pxc2 se unió
echo "    Verificando unión de pxc2..."
PXC2_JOINED=$(docker exec pxc1 mysql -uroot -proot -NB -e \
  "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print $2}' || echo "0")

if [ "$PXC2_JOINED" = "2" ]; then
    echo -e "${GREEN}    ✅ pxc2 se unió (2 nodos)${NC}"
else
    echo -e "${RED}    ❌ pxc2 NO se unió (solo $PXC2_JOINED nodos)${NC}"
    echo "    Intentando forzar unión..."
    # Forzar en pxc2
    docker exec pxc2 mysql -uroot -proot -e \
      "SET GLOBAL wsrep_cluster_address='gcomm://10.99.88.10,10.99.88.11,10.99.88.12';" 2>/dev/null || true
    sleep 15
fi

# 6. INICIAR PXC3
echo -e "${YELLOW}[6/7] Iniciando pxc3...${NC}"
docker compose up -d pxc3

echo -e "${YELLOW}    Esperando 30 segundos...${NC}"
sleep 30

# 7. VERIFICACIÓN FINAL
echo -e "${YELLOW}[7/7] Verificación final...${NC}"
for i in {1..10}; do
    SIZE=$(docker exec pxc1 mysql -uroot -proot -NB -e \
        "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null \
        | awk '{print $2}' 2>/dev/null || echo "0")
    
    echo "    Check $i/10 - Nodos: $SIZE"
    
    if [ "$SIZE" = "3" ]; then
        echo ""
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}     🎉 CLUSTER DE 3 NODOS OPERATIVO 🎉${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo ""
        
        # Mostrar todos los nodos
        docker exec pxc1 mysql -uroot -proot -e "
          SELECT 'Estado Cluster' as '---';
          SELECT 'Nodos: ' as '', VARIABLE_VALUE as '' 
          FROM performance_schema.global_status 
          WHERE VARIABLE_NAME = 'wsrep_cluster_size'
          UNION
          SELECT 'Ready: ', VARIABLE_VALUE
          WHERE VARIABLE_NAME = 'wsrep_ready'
          UNION
          SELECT 'Direcciones: ', VARIABLE_VALUE
          WHERE VARIABLE_NAME = 'wsrep_incoming_addresses';" 2>/dev/null || true
        
        echo ""
        echo "Conectar:"
        echo "  pxc1: mysql -h127.0.0.1 -P33061 -uroot -proot"
        echo "  pxc2: mysql -h127.0.0.1 -P33062 -uroot -proot"
        echo "  pxc3: mysql -h127.0.0.1 -P33063 -uroot -proot"
        
        exit 0
    fi
    
    sleep 10
done

echo ""
echo -e "${RED}════════════════════════════════════════${NC}"
echo -e "${RED}     ⚠️  Cluster incompleto ($SIZE nodos)${NC}"
echo -e "${RED}════════════════════════════════════════${NC}"

# Diagnóstico detallado
echo ""
echo "=== DIAGNÓSTICO DETALLADO ==="
for node in pxc1 pxc2 pxc3; do
    if docker ps | grep -q $node; then
        echo "--- $node ---"
        docker exec $node mysql -uroot -proot -e \
          "SHOW VARIABLES LIKE 'wsrep%address'; SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null || echo "  No conecta"
    else
        echo "--- $node NO está corriendo ---"
    fi
done

exit 1