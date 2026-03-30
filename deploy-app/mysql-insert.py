#!/usr/bin/env python3
"""
Simple Python script to insert rows into a MySQL database.
Database connection parameters are read from environment variables.
"""

import os
import sys
import time
import mysql.connector
from mysql.connector import Error


def get_db_config():
    """Get database configuration from environment variables."""
    config = {
        'host': os.getenv('DB_HOST', 'localhost'),
        'port': int(os.getenv('DB_PORT', 3306)),
        'user': os.getenv('DB_USERNAME'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME', 'testdb'),
        'batch_size': int(os.getenv('BATCH_SIZE', 100)),
        'batch_count': int(os.getenv('BATCH_COUNT', 10)),
        'sleep_ms': int(os.getenv('SLEEP_MS', 1000)),
        'message_length': int(os.getenv('MESSAGE_LENGTH', 1000)),
    }
    
    # Check for required environment variables
    if not config['user'] or not config['password']:
        print("Error: DB_USERNAME and DB_PASSWORD environment variables are required")
        sys.exit(1)
    
    return config


def create_connection(config):
    """Create a database connection."""
    try:
        connection = mysql.connector.connect(user=config['user'], password=config['password'], host=config['host'], port=config['port'], database=config['database'])
        if connection.is_connected():
            print(f"Successfully connected to MySQL database at {config['host']}:{config['port']}")
            return connection
    except Error as e:
        print(f"Error connecting to MySQL: {e}")
        return None


def create_sample_table(connection):
    """Create a sample table for demonstration."""
    cursor = connection.cursor()
    
    create_table_query = """
    CREATE TABLE IF NOT EXISTS messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        created_at DATE NOT NULL,
        message TEXT NOT NULL
    )
    """
    
    try:
        cursor.execute(create_table_query)
        connection.commit()
        print("Sample table 'messages' created successfully")
    except Error as e:
        print(f"Error creating table: {e}")
    finally:
        cursor.close()


def insert_sample_data(connection, batch_size, message_length):
    """Insert sample data into the messages table."""
    cursor = connection.cursor()
        
    insert_query = """
    INSERT INTO messages (created_at, message)
    VALUES (NOW(), %s)
    """
    # Data to insert with a given batch size and messages with a given length using [index padded zeros]-[remaining length]
    messages_data = [ ( str(i).zfill(9) + "".rjust(message_length - 9,'.'), ) for i in range(batch_size) ]
    try:
        cursor.executemany(insert_query, messages_data)
        connection.commit()
        print(f"Successfully inserted {cursor.rowcount} rows into messages table")
        
        # Print count of rows in table 
        cursor.execute("SELECT COUNT(*) FROM messages")
        count = cursor.fetchone()[0]
        print(f"Total number of rows in messages table: {count}")
        # Display inserted data
        cursor.execute("SELECT * FROM messages ORDER BY id DESC LIMIT 1")
        rows = cursor.fetchall()
        
        print("\nRecently inserted messages:")
        print("-" * 80)
        print(f"{'ID':<5} {'Date':<12} {'Message':<60}")
        print("-" * 80)
        
        for row in rows:
            print(f"{row[0]:<5} {str(row[1]):<12} {row[2]:<60}")
            
    except Error as e:
        # Print error and throw exception
        print(f"Error inserting data: {e}")
        connection.rollback()
        raise e
    finally:
        cursor.close()


def main():
    """Main function to demonstrate MySQL insertion."""
    print("MySQL Database Insert Script")
    print("=" * 40)
    
    # Get database configuration
    config = get_db_config()
    print(f"Connecting to database '{config['database']}' at {config['host']}:{config['port']}")
    
    # Create connection
    connection = create_connection(config)
    # Reconnect forever if connection lost

    if not connection:
        sys.exit(1)
    
    try:
        # Create sample table
        # create_sample_table(connection)
        
        # Insert sample data in batches
        for i in range(config['batch_count']):
            try:
                print(f"\n--- Batch {i + 1}/{config['batch_count']} ---")
                insert_sample_data(connection, config['batch_size'], config['message_length'])
                print(f"Sleeping for {config['sleep_ms']} ms...")
                time.sleep(config['sleep_ms'] / 1000)
            except mysql.connector.errors.OperationalError:
                    print("Connection lost. Reconnecting...")
                    connection.reconnect(attempts=24*60*12, delay=5) 
            
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if connection.is_connected():
            connection.close()
            print("\nMySQL connection closed")


if __name__ == "__main__":
    main()