#!/bin/bash
set -e

echo "========================================"
echo "     LIMPIEZA COMPLETA DOCKER"
echo "========================================"

# COLORES
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[1/8] Deteniendo TODOS los contenedores relacionados...${NC}"

# Detener TODOS los contenedores que puedan estar relacionados
docker stop $(docker ps -a -q --filter "name=pxc" --filter "name=galera" --filter "name=haproxy") 2>/dev/null || true
docker stop $(docker ps -a -q) 2>/dev/null || true  # ¡CUIDADO! Esto para TODOS los contenedores

echo -e "${YELLOW}[2/8] Eliminando contenedores...${NC}"
docker rm -f $(docker ps -a -q --filter "name=pxc" --filter "name=galera" --filter "name=haproxy") 2>/dev/null || true

echo -e "${YELLOW}[3/8] Eliminando VOLÚMENES de Galera...${NC}"
docker volume rm $(docker volume ls -q | grep -E "pxc|galera|mysql|data") 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

echo -e "${YELLOW}[4/8] Eliminando REDES conflictivas...${NC}"
# Listar TODAS las redes primero
echo "Redes encontradas:"
docker network ls --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}"

# Eliminar redes relacionadas
docker network rm $(docker network ls -q --filter "name=galera" --filter "name=pxc") 2>/dev/null || true
docker network rm galera-network galera-net galera-docker_galera-network 2>/dev/null || true

# Eliminar redes no utilizadas (pero NO bridge, host, none)
docker network prune -f 2>/dev/null || true

echo -e "${YELLOW}[5/8] Eliminando IMÁGENES huérfanas...${NC}"
docker image prune -a -f 2>/dev/null || true

echo -e "${YELLOW}[6/8] Limpiando sistema Docker...${NC}"
docker system prune -a -f --volumes 2>/dev/null || true

echo -e "${YELLOW}[7/8] Verificando procesos MySQL residuales...${NC}"
# Buscar procesos MySQL que puedan estar bloqueando puertos
sudo pkill -9 mysql 2>/dev/null || true
sudo pkill -9 mysqld 2>/dev/null || true

echo -e "${YELLOW}[8/8] Verificando puertos en uso...${NC}"
# Puertos que Galera usa
PORTS="3306 3307 33061 33062 33063 4567 4444 8404"
for port in $PORTS; do
    if sudo netstat -tulpn | grep ":$port " > /dev/null; then
        echo -e "${RED}  ⚠️  Puerto $port en uso${NC}"
        sudo netstat -tulpn | grep ":$port "
    else
        echo -e "${GREEN}  ✅ Puerto $port libre${NC}"
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}     LIMPIEZA COMPLETADA${NC}"
echo -e "${GREEN}========================================${NC}"

# Mostrar estado final
echo ""
echo "ESTADO FINAL:"
echo "Contenedores:"
docker ps -a

echo ""
echo "Redes:"
docker network ls

echo ""
echo "Volúmenes:"
docker volume ls

echo ""
echo -e "${YELLOW}✅ Sistema limpio. Ahora puedes ejecutar:${NC}"
echo -e "${GREEN}./start-final.sh${NC}"