#!/bin/sh

# Set default values for database credentials, allowing override via environment variables
DB_USER=${DB_USER:-root}
DB_PASS=${DB_PASS:-123456}
DB_NAME=${DB_NAME:-new_api}

# Check if the database is initialized
if [ ! -d "/data/postgres/base" ]; then
    echo "Initializing PostgreSQL database..."
    mkdir -p /data/postgres
    chown -R postgres:postgres /data/postgres
    chmod 700 /data/postgres

    # Initialize the database cluster
    su-exec postgres initdb -D /data/postgres

    # Start postgres temporarily to perform initialization
    su-exec postgres pg_ctl -D /data/postgres -o "-h '*' -p 5432" -l /dev/null start

    # Wait for postgres to be ready
    until su-exec postgres pg_isready -h 127.0.0.1 -p 5432 -q; do
      echo "Waiting for postgres to be ready..."
      sleep 1
    done

    # Create the user and a database owned by that user.
    echo "Creating user '$DB_USER' and database '$DB_NAME'..."
    su-exec postgres psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
        CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
        CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
EOSQL

    # Configure postgres to accept external connections
    echo "host all all 0.0.0.0/0 md5" >> /data/postgres/pg_hba.conf
    echo "host all all ::/0 md5" >> /data/postgres/pg_hba.conf

    # Stop the temporary postgres instance
    su-exec postgres pg_ctl -D /data/postgres stop
fi

# Use sed to reliably set listen_addresses for postgres
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /data/postgres/postgresql.conf

# Also ensure Redis listens on all interfaces
if [ -f /etc/redis.conf ]; then
    sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/' /etc/redis.conf
elif [ -f /etc/redis/redis.conf ]; then
    sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
fi

# Ensure all necessary directories exist before starting services
mkdir -p /data/logs /data/redis /data/postgres
chown -R postgres:postgres /data/postgres
chmod 700 /data/postgres

# Start all services via supervisord
echo "Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisord.conf