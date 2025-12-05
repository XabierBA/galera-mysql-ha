#!/usr/bin/env bash
set -e

ROOTPWD="rootpw"

echo "======================================================"
echo "     INICIANDO CLÚSTER PERCONA XTRADB + HAPROXY"
echo "======================================================"

# ---------------------------------------
# 1) LEVANTAR CONTENEDORES
# ---------------------------------------
echo "[INFO] Levantando contenedores..."
docker compose up -d >/dev/null 2>&1
echo "[OK] Contenedores iniciados."

# ---------------------------------------
# 2) ESPERA DE ARRANQUE
# ---------------------------------------
echo "[INFO] Esperando 20s para que los nodos arranquen..."
sleep 20

# ---------------------------------------
# 3) SALUD DE CONTENEDORES
# ---------------------------------------
echo "[INFO] Estado de contenedores:"
docker ps --format "{{.Names}}  {{.Status}}" | grep pxc
echo "[OK] Contenedores activos."

# ---------------------------------------
# 4) ESPERA ACTIVA DEL CLÚSTER COMPLETO
# ---------------------------------------
echo "[INFO] Esperando a que el clúster alcance 3 nodos..."

for i in {1..30}; do
    SIZE=$(docker exec pxc1 mysql -uroot -p${ROOTPWD} -NB -e \
        "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null \
        | awk '{print $2}')

    echo -n " → Tamaño actual del cluster: $SIZE\r"

    if [ "$SIZE" = "3" ]; then
        echo -e "\n[OK] Los 3 nodos están sincronizados."
        break
    fi

    sleep 2
done

if [ "$SIZE" != "3" ]; then
    echo -e "\n[ERROR] El clúster no llegó a 3 nodos. Revisa logs."
fi

# ---------------------------------------
# 5) ESTADO WSREP FINAL
# ---------------------------------------
echo "[INFO] Estado WSREP del nodo principal:"
docker exec pxc1 mysql -uroot -p${ROOTPWD} -e \
"SHOW STATUS LIKE 'wsrep_ready';
 SHOW STATUS LIKE 'wsrep_local_state_comment';"

# ---------------------------------------
# 6) CARGAR BASE DE DATOS (SI EXISTE)
# ---------------------------------------
echo "[INFO] Inicializando base de datos..."
if [ -f ./init_db.sql ]; then
    docker exec -i pxc1 mysql -uroot -p${ROOTPWD} < init_db.sql
    echo "[OK] Base de datos cargada."
else
    echo "[WARN] No existe init_db.sql, saltando."
fi

# ---------------------------------------
# 7) ABRIR PANEL HAPROXY
# ---------------------------------------
echo "[INFO] Abriendo panel HAProxy..."
xdg-open "http://localhost:8404/stats" >/dev/null 2>&1 || \
echo "[WARN] No se pudo abrir automáticamente. Accede a http://localhost:8404/stats"

# ---------------------------------------
# 8) ABRIR UNA TERMINAL POR NODO
# ---------------------------------------
echo "[INFO] Abriendo terminales para pxc1, pxc2 y pxc3..."

if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="pxc1" -- bash -c "docker exec -it pxc1 bash; exec bash" &
    gnome-terminal --title="pxc2" -- bash -c "docker exec -it pxc2 bash; exec bash" &
    gnome-terminal --title="pxc3" -- bash -c "docker exec -it pxc3 bash; exec bash" &
else
    echo "[WARN] gnome-terminal no está instalado. Instálalo con:"
    echo "       sudo apt install gnome-terminal -y"
fi

# ---------------------------------------
# 9) LOGS EN TIEMPO REAL
# ---------------------------------------
echo "[INFO] Monitoreando logs de los nodos (CTRL + C para salir)"
docker logs -f pxc1 &
docker logs -f pxc2 &
docker logs -f pxc3 &
wait
