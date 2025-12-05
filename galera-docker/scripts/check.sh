#!/usr/bin/env bash
set -e

ROOTPWD="rootpw"

echo "======================================================"
echo "    MONITOREANDO ESTADO DEL CLÚSTER PXC"
echo "======================================================"

docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo " Estado WSREP por nodo:"
for n in pxc1 pxc2 pxc3; do
  echo ""
  echo "------ $n ------"
  docker exec $n mysql -uroot -p${ROOTPWD} -e \
  "SHOW STATUS LIKE 'wsrep_cluster_size';
   SHOW STATUS LIKE 'wsrep_ready';
   SHOW STATUS LIKE 'wsrep_local_state_comment';
   SHOW STATUS LIKE 'wsrep_flow_control_paused';
   SHOW STATUS LIKE 'wsrep_last_committed';
   SHOW STATUS LIKE 'wsrep_cert_deps_distance';"
done

echo "======================================================"
echo "  Monitoreo completado."
echo "======================================================"
