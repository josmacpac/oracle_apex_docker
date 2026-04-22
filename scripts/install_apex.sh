#!/bin/bash

# --- CONFIGURACIÓN ---
# Ruta según tu volumen: - ./apex/apex:/home/oracle/apex_install
APEX_PATH="/home/oracle/apex_install"
PASS="Password123$"
PDB_NAME="ORCLPDB1"

echo "==========================================================="
echo " INICIANDO INSTALACIÓN AUTOMATIZADA DE APEX 20.1"
echo "==========================================================="

# 1. Validar que el volumen de APEX tiene los archivos
if [ ! -f "$APEX_PATH/apexins.sql" ]; then
    echo "ERROR: No se encuentra apexins.sql en $APEX_PATH"
    echo "Revisa el mapeo de tu volumen en el docker-compose."
    exit 1
fi

# 2. Cambiar al directorio de APEX (Crucial para que SQL*Plus vea los archivos)
cd "$APEX_PATH"

# 3. Ejecutar Instalación Principal
echo "--> Pasando a Fase 1: Instalación (apexins.sql)..."
sqlplus -s / as sysdba <<EOF
    ALTER SESSION SET CONTAINER = $PDB_NAME;
    @apexins.sql SYSAUX SYSAUX TEMP /i/
    EXIT;
EOF

# 4. Configurar Password de ADMIN
echo "--> Pasando a Fase 2: Password ADMIN (apxchpwd.sql)..."
sqlplus -s / as sysdba <<EOF
    ALTER SESSION SET CONTAINER = $PDB_NAME;
    @apxchpwd.sql $PASS
    EXIT;
EOF

# 5. Configurar REST y Desbloqueos
echo "--> Pasando a Fase 3: Servicios REST y ACL..."
sqlplus -s / as sysdba <<EOF
    ALTER SESSION SET CONTAINER = $PDB_NAME;
    
    -- Inyectamos respuestas para apex_rest_config.sql (Pass Listener y Pass Rest)
    @apex_rest_config.sql $PASS $PASS
    
    -- Desbloqueo de usuarios para ORDS
    ALTER USER APEX_PUBLIC_USER IDENTIFIED BY $PASS ACCOUNT UNLOCK;
    ALTER USER APEX_LISTENER IDENTIFIED BY $PASS ACCOUNT UNLOCK;
    ALTER USER APEX_REST_PUBLIC_USER IDENTIFIED BY $PASS ACCOUNT UNLOCK;
    
    -- Configuración de ACL dinámica
    DECLARE
        v_user VARCHAR2(100);
    BEGIN
        SELECT username INTO v_user FROM dba_users 
        WHERE username LIKE 'APEX_20%' AND ROWNUM = 1;
        
        DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
            host => '*',
            lower_port => 80,
            upper_port => 443,
            ace => xs$ace_type(privilege_list => xs$name_list('connect'),
                               principal_name => v_user,
                               principal_type => xs_acl.ptype_db));
    END;
    /
    COMMIT;
    EXIT;
EOF

echo "==========================================================="
echo " ¡PROCESO COMPLETADO!"
echo "==========================================================="

