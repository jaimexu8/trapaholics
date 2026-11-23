#!/bin/bash
# Creates the two application databases the backup system dumps by name
# (luckperms, coreprotect) and matching app users. Runs only on a fresh
# datadir (MariaDB docker-entrypoint-initdb.d).
set -euo pipefail

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS luckperms;
CREATE DATABASE IF NOT EXISTS coreprotect;

CREATE USER IF NOT EXISTS 'luckperms'@'%' IDENTIFIED BY '${LUCKPERMS_DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'coreprotect'@'%' IDENTIFIED BY '${COREPROTECT_DB_PASSWORD}';

GRANT ALL PRIVILEGES ON luckperms.* TO 'luckperms'@'%';
GRANT ALL PRIVILEGES ON coreprotect.* TO 'coreprotect'@'%';
FLUSH PRIVILEGES;
EOF
