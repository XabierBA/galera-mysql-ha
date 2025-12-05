#!/usr/bin/env bash
set -e

ROOTPWD="rootpw" # contraseña del root, nada original xd, guardada en una variable

echo "======================================================"
echo "      INICIANDO CLÚSTER PERCONA XTRADB + HAPROXY"
echo "======================================================"

echo " 1) Levantando contenedores"
docker-compose up -d

echo " 2) Esperando a que pxc1 se inicialice (60s)"
sleep 60 # esto es por buenas practicas, para esperar a q se arranque y haga bootstrap

echo " 3) Verificando salud de contenedores:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo " 4) Verificando wsrep en pxc1..."
docker exec pxc1 mysql -uroot -p${ROOTPWD} -e \
"SHOW STATUS LIKE 'wsrep_cluster_size'; 
 SHOW STATUS LIKE 'wsrep_ready'; 
 SHOW STATUS LIKE 'wsrep_local_state_comment';"

echo " 5) Inicializando base de datos de ejemplo"
if [ -f ./init_db.sql ]; then
    docker exec -i pxc1 mysql -uroot -p${ROOTPWD} < ./init_db.sql # ejecuta el archivo de la base de datos
    echo "✔ Base de datos inicializada."
else
    echo "⚠ No existe init_db.sql, saltando paso."
fi

echo " 6) Verificando estado WSREP en todos los nodos:"  # para comprobar q todo funciona correctamente
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

echo " Accede al panel de HAProxy: http://localhost:8404/stats"

# Abrir el panel web automáticamente (solo Linux/macOS)
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "http://localhost:8404/stats"
elif command -v open >/dev/null 2>&1; then
  open "http://localhost:8404/stats"
fi

echo ""
echo " 7) Abriendo consola MySQL a través de HAProxy"
sleep 3
docker exec -it pxc1 mysql -uroot -p${ROOTPWD} &

echo ""
echo " 8) Mostrando logs en tiempo real de los nodos"
echo "(CTRL + C para salir)"
docker logs -f pxc1 &
docker logs -f pxc2 &
docker logs -f pxc3 &
wait

