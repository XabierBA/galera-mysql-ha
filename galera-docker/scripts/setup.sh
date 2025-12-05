#!/usr/bin/env bash
set -e

ROOTPWD="rootpw"

# --- Función para imprimir en formato bonito ---
info(){ echo -e "\e[34m[INFO]\e[0m $1"; }
ok(){ echo -e "\e[32m[OK]\e[0m $1"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $1"; }
err(){ echo -e "\e[31m[ERROR]\e[0m $1"; }

echo "======================================================"
echo "     INICIANDO CLÚSTER PERCONA XTRADB + HAPROXY"
echo "======================================================"

# 1) Levantar contenedores
info "Levantando contenedores..."
docker compose up -d >/dev/null 2>&1
ok "Contenedores iniciados."

# 2) Esperar al bootstrap
info "Esperando a que el nodo pxc1 haga bootstrap (60s)..."
sleep 60

# 3) Verificar contenedores
info "Verificando estado de los contenedores..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep pxc
ok "Contenedores arriba y ejecutándose."

# 4) Chequeo WSREP pxc1
info "Comprobando estado WSREP en pxc1..."
WSREP_STATE=$(docker exec pxc1 mysql -uroot -p${ROOTPWD} -N -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" | awk '{print $2}')
CLUSTER_SIZE=$(docker exec pxc1 mysql -uroot -p${ROOTPWD} -N -e "SHOW STATUS LIKE 'wsrep_cluster_size';" | awk '{print $2}')

echo " → Cluster size: $CLUSTER_SIZE"
echo " → Estado nodo pxc1: $WSREP_STATE"

if [ "$CLUSTER_SIZE" != "3" ]; then
    warn "El cluster no está completo (size != 3)"
else
    ok "Cluster replicado correctamente."
fi

# 5) Cargar la base de datos
info "Inicializando base de datos..."
if [ -f ./init_db.sql ]; then
    docker exec -i pxc1 mysql -uroot -p${ROOTPWD} < ./init_db.sql
    ok "Base de datos cargada."
else
    warn "No se encontró init_db.sql."
fi

# 6) Estado WSREP en cada nodo
info "Comprobando estado WSREP en todos los nodos..."
for n in pxc1 pxc2 pxc3; do
    STATE=$(docker exec $n mysql -uroot -p${ROOTPWD} -N -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" | awk '{print $2}')
    echo " → $n: $STATE"
done
ok "Todos los estados WSREP verificados."

# 7) Abrir panel de HAProxy
info "Abriendo panel HAProxy..."
xdg-open "http://localhost:8404/stats" >/dev/null 2>&1 || warn "No se pudo abrir el navegador."

# 8) Abrir una terminal por contenedor
info "Abriendo terminales para cada nodo..."
if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -c "docker exec -it pxc1 bash; exec bash" &
    gnome-terminal -- bash -c "docker exec -it pxc2 bash; exec bash" &
    gnome-terminal -- bash -c "docker exec -it pxc3 bash; exec bash" &
    ok "Terminales abiertas."
else
    warn "gnome-terminal no está instalado. Usa: sudo apt install gnome-terminal -y"
fi

echo ""
echo "======================================================"
echo "         CLÚSTER LISTO Y FUNCIONANDO ✔"
echo "======================================================"
