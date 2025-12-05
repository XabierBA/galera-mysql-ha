#!/usr/bin/env bash
set -e

ROOTPWD="rootpw"

echo "Arrancando contenedores"
docker-compose up -d

echo "Esperando a que el primer nodo se inicialice (60s)"
sleep 60

echo "Verificando estado wsrep en pxc1"
docker exec -it pxc1 mysql -uroot -p${ROOTPWD} -e "SHOW STATUS LIKE 'wsrep_cluster_size'; SHOW STATUS LIKE 'wsrep_ready';"

echo "Inicializando base de datos de prueba"
docker exec -i pxc1 mysql -uroot -p${ROOTPWD} < ./init_db.sql

echo "Estado del cluster (wsrep) en cada nodo:"
for n in pxc1 pxc2 pxc3; do
  echo "------ $n ------"
  docker exec -it $n mysql -uroot -p${ROOTPWD} -e "SHOW STATUS LIKE 'wsrep_%';"
done

echo "HAProxy stats: http://localhost:8404/stats"
echo "Accede a MySQL a través de 127.0.0.1:3306 (usuario root)"
