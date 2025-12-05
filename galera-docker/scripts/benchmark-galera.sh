#!/bin/bash

ROOTPW="rootpw"
DB="olimpiadas"
LOGFILE="./logs/galera_benchmark_$(date +%Y%m%d_%H%M%S).log"
NODES=("pxc1" "pxc2" "pxc3")
mkdir -p logs

echo "====================================" | tee -a $LOGFILE
echo "         BENCHMARK GALERA           " | tee -a $LOGFILE
echo "====================================" | tee -a $LOGFILE


# ============================================================
# 1. VERIFICACIÓN DE QUE LA BASE EXISTE
# ============================================================
echo "[1/7] Verificando base de datos existente '$DB'..." | tee -a $LOGFILE

#Ejecuta en pxc1 una consulta para comprobar que la base existe.-ss hace output “sin cabeceras”.
EXISTS=$(docker exec pxc1 mysql -uroot -p$ROOTPW -e "SHOW DATABASES LIKE '$DB';" -ss) 

if [[ "$EXISTS" != "$DB" ]]; then
  echo " ERROR: La base '$DB' no existe. Ejecuta setup.sh primero."
  exit 1
else
  echo " Base existente detectada" | tee -a $LOGFILE
fi


# ============================================================
# 2. CARGA MASIVA DE DATOS
# ============================================================
echo "[2/7] Insertando 100.000 registros..." | tee -a $LOGFILE

START=$(date +%s)

docker exec -i pxc1 mysql -uroot -p$ROOTPW $DB <<EOF

-- ===========================================
-- CARGA MASIVA (STRESS TEST DE INSERCIÓN)
-- ===========================================

-- 200 países
INSERT INTO PAIS (cod_iso,nombre)
SELECT LPAD(id,3,'0'), CONCAT('Pais_',id)
FROM (SELECT @r:=@r+1 id FROM (SELECT 0 FROM information_schema.columns LIMIT 200)a,(SELECT @r:=0)b)x
ON DUPLICATE KEY UPDATE nombre = VALUES(nombre);

-- 20.000 participantes
INSERT INTO PARTICIPANTE (id_participante,nombre,tipo,cod_iso)
SELECT id, CONCAT('Participante_',id),
       IF(RAND() > 0.5,'A','E'),
       LPAD(FLOOR(1 + RAND()*200),3,'0')
FROM (SELECT @p:=@p+1 id FROM (SELECT 0 FROM information_schema.columns LIMIT 20000)c,(SELECT @p:=0)d)x
ON DUPLICATE KEY UPDATE nombre = VALUES(nombre);

-- 10.000 atletas
INSERT INTO ATLETA (dni,edad,genero,id_participante)
SELECT CONCAT('DNI',id),
       FLOOR(18+RAND()*20),
       IF(RAND() > 0.5,'M','F'),
       id
FROM PARTICIPANTE WHERE tipo='A'
LIMIT 10000
ON DUPLICATE KEY UPDATE edad = VALUES(edad);

-- 500 sedes
INSERT INTO SEDE (id_sede,nombre,ciudad,aforo,cod_iso,anho)
SELECT id,
       CONCAT('Sede_',id),
       CONCAT('Ciudad_',id),
       FLOOR(2000+RAND()*20000),
       LPAD(FLOOR(1 + RAND()*200),3,'0'),
       FLOOR(1990 + RAND()*35)
FROM (SELECT @s:=@s+1 id FROM (SELECT 0 FROM information_schema.columns LIMIT 500)g,(SELECT @s:=0)h)x
ON DUPLICATE KEY UPDATE nombre=VALUES(nombre);

-- Asegurar medallas
INSERT INTO MEDALLA VALUES
(1,'ORO'),(2,'PLATA'),(3,'BRONCE')
ON DUPLICATE KEY UPDATE tipo=VALUES(tipo);

-- 70.000 eventos = carga fuerte
INSERT INTO EVENTO (fecha,id_deporte,id_disciplina,id_sede,id_medalla,id_participante)
SELECT
  DATE('2024-01-01') + INTERVAL FLOOR(RAND()*365) DAY,
  FLOOR(1 + RAND()*10),
  FLOOR(1 + RAND()*200),
  FLOOR(1 + RAND()*500),
  FLOOR(1 + RAND()*3),
  FLOOR(1 + RAND()*20000)
FROM (SELECT 1 FROM information_schema.columns LIMIT 70000)x;

EOF

END=$(date +%s)
TIME=$((END-START))

echo "✔ 100.000 registros en $TIME s" | tee -a $LOGFILE
echo "TPS estimado: $((100000 / TIME))" | tee -a $LOGFILE


# ============================================================
# 3. CONTADORES POR NODO
# ============================================================
echo "[3/7] Contando registros en cada nodo..." | tee -a $LOGFILE

TABLAS=(PAIS PARTICIPANTE ATLETA SEDE EVENTO)

for nodo in "${NODES[@]}"; do
  echo "--- $nodo ---" | tee -a $LOGFILE
  for t in "${TABLAS[@]}"; do
    COUNT=$(docker exec -i $nodo mysql -uroot -p$ROOTPW -ss -e "SELECT COUNT(*) FROM $DB.$t")
    echo "$t: $COUNT" | tee -a $LOGFILE
  done
done


# ============================================================
# 4. MÉTRICAS DEL CLÚSTER
# ============================================================
echo "[4/7] Obteniendo métricas de Galera..." | tee -a $LOGFILE

METRICAS=(
wsrep_cluster_size
wsrep_local_state_comment
wsrep_local_cert_failures
wsrep_local_bf_aborts
wsrep_flow_control_paused
wsrep_flow_control_sent
wsrep_flow_control_recv
wsrep_cert_deps_distance
)

for nodo in "${NODES[@]}"; do
  echo "---- $nodo ----" | tee -a $LOGFILE
  for m in "${METRICAS[@]}"; do
    docker exec -i $nodo mysql -uroot -p$ROOTPW -ss -e \
    "SHOW GLOBAL STATUS LIKE '$m';" | tee -a $LOGFILE
  done
done


# ============================================================
# 5. CONSISTENCIA GLOBAL
# ============================================================
echo "[5/7] Verificando que todos los nodos tienen los mismos datos..." | tee -a $LOGFILE

docker exec -i pxc1 mysql -uroot -p$ROOTPW -e "CHECKSUM TABLE $DB.EVENTO;" >> $LOGFILE
docker exec -i pxc2 mysql -uroot -p$ROOTPW -e "CHECKSUM TABLE $DB.EVENTO;" >> $LOGFILE
docker exec -i pxc3 mysql -uroot -p$ROOTPW -e "CHECKSUM TABLE $DB.EVENTO;" >> $LOGFILE

echo "✔ CHECKSUM realizado" | tee -a $LOGFILE


# ============================================================
# 6. RESUMEN FINAL
# ============================================================
echo "[6/7] Resumen:" | tee -a $LOGFILE
echo "Tiempo total: $TIME s" | tee -a $LOGFILE
echo "TPS: $((100000 / TIME))" | tee -a $LOGFILE


# ============================================================
# 7. FINAL
# ============================================================
echo "[7/7] Benchmark finalizado" | tee -a $LOGFILE
echo "Log generado en: $LOGFILE" | tee -a $LOGFILE
