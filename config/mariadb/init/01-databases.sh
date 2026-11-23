#!/bin/bash
# Creates (or repairs) the two application databases the backup system dumps by
# name (luckperms, coreprotect) and matching app users.
#
# MariaDB only auto-runs scripts in /docker-entrypoint-initdb.d on an *empty*
# datadir. This script is idempotent so DEPLOY can also run it by hand when
# ./mariadb already exists:
#   docker exec mariadb /docker-entrypoint-initdb.d/01-databases.sh
set -euo pipefail

: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set}"
: "${LUCKPERMS_DB_PASSWORD:?LUCKPERMS_DB_PASSWORD must be set}"
: "${COREPROTECT_DB_PASSWORD:?COREPROTECT_DB_PASSWORD must be set}"

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS luckperms;
CREATE DATABASE IF NOT EXISTS coreprotect;

CREATE USER IF NOT EXISTS 'luckperms'@'%' IDENTIFIED BY '${LUCKPERMS_DB_PASSWORD}';
CREATE USER IF NOT EXISTS 'coreprotect'@'%' IDENTIFIED BY '${COREPROTECT_DB_PASSWORD}';

-- Always re-apply passwords/grants so a re-run after .env rotation (or a
-- pre-existing datadir) leaves accounts usable.
ALTER USER 'luckperms'@'%' IDENTIFIED BY '${LUCKPERMS_DB_PASSWORD}';
ALTER USER 'coreprotect'@'%' IDENTIFIED BY '${COREPROTECT_DB_PASSWORD}';

GRANT ALL PRIVILEGES ON luckperms.* TO 'luckperms'@'%';
GRANT ALL PRIVILEGES ON coreprotect.* TO 'coreprotect'@'%';
FLUSH PRIVILEGES;
EOF

echo "01-databases.sh: luckperms + coreprotect OK"
