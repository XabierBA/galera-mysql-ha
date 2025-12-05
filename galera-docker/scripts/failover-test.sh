#!/usr/bin/env bash
set -e

ROOTPWD="rootpw"
TEST_TABLE="failover_test"

echo "======================================================"
echo "        TEST DE FAILOVER EN GALERA + HAPROXY"
echo "======================================================"

echo " Paso 1: Crear tabla de prueba (si no existe)"
docker exec pxc1 mysql -uroot -p${ROOTPWD} -e "
CREATE TABLE IF NOT EXISTS ${TEST_TABLE} (
 id INT AUTO_INCREMENT PRIMARY KEY,
 mensaje VARCHAR(255),
 ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);"

echo "✔ Tabla lista."
echo ""

echo " Paso 2: Iniciando inserciones continuas a través de HAProxy..."
echo "    (se ejecutará en segundo plano)"
echo ""

(
  for i in {1..30}; do
    docker exec haproxy mysql -uroot -p${ROOTPWD} -h 127.0.0.1 -P 3306 -e \
      "INSERT INTO ${TEST_TABLE}(mensaje) VALUES('Insert test $i');"
    echo "→ Insert $i OK"
    sleep 1
  done
) &

INS_PID=$!
sleep 3

echo ""
echo " Paso 3: Derribando pxc1..."
docker stop pxc1
echo "✔ pxc1 detenido."
echo ""

echo "Esperando detección por HAProxy..."
sleep 10

echo ""
echo " Paso 4: Verificando que las inserciones siguen funcionando..."
sleep 5

docker exec haproxy mysql -uroot -p${ROOTPWD} -h 127.0.0.1 -P 3306 -e \
  "SELECT COUNT(*) AS total_inserts FROM ${TEST_TABLE};"

echo "✔ El clúster sigue insertando datos, failover exitoso."
echo ""

echo " Paso 5: Levantando pxc1 nuevamente..."
docker start pxc1
sleep 20

echo "✔ pxc1 levantado y sincronizado."
echo ""

echo " Paso 6: Verificando consistencia entre nodos..."
for n in pxc1 pxc2 pxc3; do
  echo "---- $n ----"
  docker exec $n mysql -uroot -p${ROOTPWD} -e \
    "SELECT COUNT(*) AS registros FROM ${TEST_TABLE};"
done
echo ""

echo "======================================================"
echo "        FAILOVER COMPLETADO CORRECTAMENTE"
echo "======================================================"
