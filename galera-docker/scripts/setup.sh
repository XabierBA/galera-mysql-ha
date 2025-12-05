#!/usr/bin/env bash
set -e

ROOTPWD="rootpw"  # Contraseña root

echo "======================================================"
echo "      INICIANDO CLÚSTER PERCONA XTRADB + HAPROXY"
echo "======================================================"

echo " 1) Levantando contenedores..."
docker compose up -d

echo " 2) Esperando a que pxc1 se inicialice (60s)..."
sleep 60

echo " 3) Verificando salud de contenedores:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo " 4) Verificando estado wsrep en pxc1..."
docker exec pxc1 mysql -uroot -p${ROOTPWD} -e \
"SHOW STATUS LIKE 'wsrep_cluster_size';
 SHOW STATUS LIKE 'wsrep_ready';
 SHOW STATUS LIKE 'wsrep_local_state_comment';"

echo " 5) Inicializando base de datos de ejemplo..."
if [ -f ./init_db.sql ]; then
    docker exec -i pxc1 mysql -uroot -p${ROOTPWD} < ./init_db.sql
    echo "✔ Base de datos inicializada."
else
    echo "⚠ No existe init_db.sql, saltando paso."
fi

echo " 6) Verificando estado WSREP en todos los nodos:"
for n in pxc1 pxc2 pxc3; do
  echo ""
  echo "------ Estado de $n ------"
  docker exec $n mysql -uroot -p${ROOTPWD} -e \
  "SHOW STATUS LIKE 'wsrep_cluster_size';
   SHOW STATUS LIKE 'wsrep_ready';
   SHOW STATUS LIKE 'wsrep_local_state_comment';"
done

echo ""
echo "======================================================"
echo "         CLUSTER LISTO Y FUNCIONANDO"
echo "======================================================"
echo ""
echo " Accede al panel de HAProxy: http://localhost:8404/stats"
echo ""

# ======================================================
# 7) ABRIR PANEL WEB DE HAPROXY
# ======================================================

echo " → Abriendo panel HAProxy en navegador..."
xdg-open "http://localhost:8404/stats" >/dev/null 2>&1 &
sleep 2

# ======================================================
# 8) ABRIR UNA TERMINAL POR CADA NODO DEL CLÚSTER
# ======================================================

echo " → Abriendo una terminal separada para cada contenedor..."

if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -c "docker exec -it pxc1 bash; exec bash" &
    gnome-terminal -- bash -c "docker exec -it pxc2 bash; exec bash" &
    gnome-terminal -- bash -c "docker exec -it pxc3 bash; exec bash" &
else
    echo "  gnome-terminal no está instalado. Instálalo con:"
    echo "   sudo apt install gnome-terminal -y"
fi

sleep 2

# ======================================================
# 9) MOSTRAR LOGS EN TIEMPO REAL
# ======================================================

echo ""
echo " → Mostrando logs en tiempo real de los nodos (CTRL + C para salir)"
docker logs -f pxc1 &
docker logs -f pxc2 &
docker logs -f pxc3 &
wait
