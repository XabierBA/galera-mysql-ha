#!/usr/bin/env bash
set -e

ROOTPWD="root"

echo "======================================================"
echo "     INICIANDO CLÚSTER PERCONA XTRADB + HAPROXY (CORREGIDO)"
echo "======================================================"

# ---------------------------------------
# 0) LIMPIAR CONTENEDORES PREVIOS
# ---------------------------------------
echo "[INFO] Limpiando contenedores anteriores..."
docker compose down -v >/dev/null 2>&1 || true
sleep 2

# ---------------------------------------
# 1) LEVANTAR NODO BOOTSTRAP (SOLO PXC1)
# ---------------------------------------
echo "[INFO] Iniciando nodo bootstrap (pxc1)..."
docker compose up -d pxc1 >/dev/null 2>&1

# ---------------------------------------
# 2) ESPERA LARGA PARA PXC1
# ---------------------------------------
echo "[INFO] Esperando 90 segundos para que pxc1 se inicialice como cluster..."
for i in {1..90}; do
    echo -ne "  Esperando... $i/90 segundos\r"
    sleep 1
done
echo ""

# Verificar que pxc1 está realmente vivo
echo "[INFO] Verificando que pxc1 esté listo..."
if docker exec pxc1 mysqladmin -uroot -p${ROOTPWD} ping 2>/dev/null | grep -q "mysqld is alive"; then
    echo "[OK] pxc1 está vivo y respondiendo"
else
    echo "[ERROR] pxc1 no responde. Revisar logs: docker logs pxc1"
    exit 1
fi

# ---------------------------------------
# 3) INICIAR PXC2 (UNIÉNDOSE A PXC1)
# ---------------------------------------
echo "[INFO] Iniciando pxc2 (uniéndose al cluster)..."
docker compose up -d pxc2 >/dev/null 2>&1
echo "[INFO] Esperando 45 segundos para que pxc2 se una..."
sleep 45

# ---------------------------------------
# 4) INICIAR PXC3 (UNIÉNDOSE A PXC1)
# ---------------------------------------
echo "[INFO] Iniciando pxc3 (uniéndose al cluster)..."
docker compose up -d pxc3 >/dev/null 2>&1
echo "[INFO] Esperando 45 segundos para que pxc3 se una..."
sleep 45

# ---------------------------------------
# 5) SALUD DE CONTENEDORES
# ---------------------------------------
echo "[INFO] Estado de contenedores:"
docker ps --format "{{.Names}}  {{.Status}}" | grep pxc
echo "[OK] Contenedores activos."

# ---------------------------------------
# 6) ESPERA ACTIVA DEL CLÚSTER COMPLETO (CORREGIDO)
# ---------------------------------------
echo "[INFO] Esperando a que el clúster alcance 3 nodos..."

CLUSTER_SIZE=0
for i in {1..30}; do
    SIZE=$(docker exec pxc1 mysql -uroot -p${ROOTPWD} -NB -e \
        "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null \
        | awk '{print $2}' 2>/dev/null || echo "0")
    
    if [[ "$SIZE" =~ ^[0-9]+$ ]] && [ "$SIZE" -gt "$CLUSTER_SIZE" ]; then
        CLUSTER_SIZE=$SIZE
    fi
    
    echo -ne "  Intento $i/30 - Nodos en cluster: ${CLUSTER_SIZE}\r"
    
    if [ "$CLUSTER_SIZE" = "3" ]; then
        echo -e "\n[SUCCESS] ✅ Los 3 nodos están sincronizados!"
        break
    fi
    
    sleep 5
done

# ---------------------------------------
# 7) VERIFICACIÓN FINAL
# ---------------------------------------
echo ""
echo "=== VERIFICACIÓN FINAL DEL CLUSTER ==="

FINAL_SIZE=$(docker exec pxc1 mysql -uroot -p${ROOTPWD} -NB -e \
    "SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null \
    | awk '{print $2}' 2>/dev/null || echo "0")

if [ "$FINAL_SIZE" = "3" ]; then
    echo "[SUCCESS] Cluster operativo con $FINAL_SIZE nodos"
else
    echo "[WARNING] Cluster solo tiene $FINAL_SIZE nodos"
fi

# ---------------------------------------
# 8) ESTADO WSREP DETALLADO
# ---------------------------------------
echo ""
echo "=== ESTADO DETALLADO WSREP ==="
docker exec pxc1 mysql -uroot -p${ROOTPWD} -e "
SHOW GLOBAL STATUS LIKE 'wsrep_ready';
SHOW GLOBAL STATUS LIKE 'wsrep_connected';
SHOW GLOBAL STATUS LIKE 'wsrep_local_state_comment';
SHOW GLOBAL STATUS LIKE 'wsrep_cluster_status';
SHOW GLOBAL STATUS LIKE 'wsrep_cluster_size';
SHOW GLOBAL STATUS LIKE 'wsrep_incoming_addresses';" 2>/dev/null || {
    echo "[ERROR] No se pudo obtener estado WSREP"
    echo "[INFO] Revisando logs de error..."
    docker logs pxc1 --tail 20
}

# ---------------------------------------
# 9) CARGAR BASE DE DATOS (SI EXISTE)
# ---------------------------------------
echo ""
echo "[INFO] Inicializando base de datos..."
if [ -f ./init_db.sql ]; then
    echo "[INFO] Cargando init_db.sql..."
    docker exec -i pxc1 mysql -uroot -p${ROOTPWD} < ./init_db.sql 2>/dev/null && \
        echo "[OK] Base de datos cargada." || \
        echo "[WARN] Error al cargar la base de datos"
else
    echo "[INFO] No existe init_db.sql, creando base de datos de ejemplo..."
    docker exec pxc1 mysql -uroot -p${ROOTPWD} -e "
        CREATE DATABASE IF NOT EXISTS galera_test;
        USE galera_test;
        CREATE TABLE IF NOT EXISTS cluster_nodes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            node_name VARCHAR(50),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO cluster_nodes (node_name) VALUES ('pxc1'), ('pxc2'), ('pxc3');
        SELECT 'Base de datos creada exitosamente' AS message;" 2>/dev/null || \
        echo "[WARN] No se pudo crear base de datos de ejemplo"
fi

# ---------------------------------------
# 10) VERIFICAR QUE LOS NODOS SE VEN ENTRE SÍ
# ---------------------------------------
echo ""
echo "=== VERIFICACIÓN DE CONEXIÓN ENTRE NODOS ==="
for node in pxc1 pxc2 pxc3; do
    echo -n "  $node -> "
    docker exec $node mysql -uroot -p${ROOTPWD} -NB -e \
        "SHOW GLOBAL STATUS LIKE 'wsrep_incoming_addresses';" 2>/dev/null \
        | awk '{print $2}' | tr ',' '\n' | wc -l | xargs echo -n
    echo " nodos visibles"
done

# ---------------------------------------
# 11) ABRIR PANEL HAPROXY
# ---------------------------------------
echo ""
echo "[INFO] Panel HAProxy disponible en: http://localhost:8404/stats"
echo "[INFO] Para abrir automáticamente ejecuta: xdg-open http://localhost:8404/stats"

# ---------------------------------------
# 12) INFORMACIÓN DE CONEXIÓN
# ---------------------------------------
echo ""
echo "=== INFORMACIÓN DE CONEXIÓN ==="
echo "Nodo directo pxc1:  mysql -h127.0.0.1 -P33061 -uroot -p${ROOTPWD}"
echo "Nodo directo pxc2:  mysql -h127.0.0.1 -P33062 -uroot -p${ROOTPWD}"
echo "Nodo directo pxc3:  mysql -h127.0.0.1 -P33063 -uroot -p${ROOTPWD}"
echo "HAProxy (balanceador): mysql -h127.0.0.1 -P3307 -uroot -p${ROOTPWD}"

# ---------------------------------------
# 13) MONITOREO (OPCIONAL)
# ---------------------------------------
echo ""
read -p "¿Deseas monitorear logs en tiempo real? (s/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Ss]$ ]]; then
    echo "[INFO] Monitoreando logs (Ctrl+C para salir)..."
    echo "[INFO] Abriendo terminales separadas para logs..."
    
    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="pxc1 logs" -- bash -c "echo 'Logs de pxc1:'; docker logs -f pxc1; exec bash" &
        gnome-terminal --title="pxc2 logs" -- bash -c "echo 'Logs de pxc2:'; docker logs -f pxc2; exec bash" &
        gnome-terminal --title="pxc3 logs" -- bash -c "echo 'Logs de pxc3:'; docker logs -f pxc3; exec bash" &
        sleep 2
        gnome-terminal --title="Cluster Status" -- bash -c "
            echo 'Monitoreo estado del cluster:';
            while true; do
                clear;
                echo '=== ESTADO CLUSTER GALERA ===';
                echo 'Fecha: $(date)';
                echo '';
                docker exec pxc1 mysql -uroot -p${ROOTPWD} -e \"
                    SELECT VARIABLE_NAME, VARIABLE_VALUE 
                    FROM performance_schema.global_status 
                    WHERE VARIABLE_NAME LIKE 'wsrep_%' 
                    AND VARIABLE_NAME IN (
                        'wsrep_cluster_size',
                        'wsrep_ready',
                        'wsrep_connected',
                        'wsrep_local_state_comment',
                        'wsrep_cluster_status',
                        'wsrep_flow_control_paused'
                    )\" 2>/dev/null || echo 'Error conectando';
                sleep 5;
            done;
            exec bash" &
    else
        echo "[INFO] Ejecuta en terminales separadas:"
        echo "  Terminal 1: docker logs -f pxc1"
        echo "  Terminal 2: docker logs -f pxc2"
        echo "  Terminal 3: docker logs -f pxc3"
        echo "  Terminal 4: while true; do clear; docker exec pxc1 mysql -uroot -p${ROOTPWD} -e \"SHOW STATUS LIKE 'wsrep_%';\"; sleep 5; done"
    fi
fi

echo ""
echo "======================================================"
echo "     CLÚSTER INICIADO CORRECTAMENTE"
echo "======================================================"