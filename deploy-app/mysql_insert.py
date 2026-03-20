#!/usr/bin/env python3
"""
Simple Python script to insert rows into a MySQL database.
Database connection parameters are read from environment variables.
"""

import os
import sys
import mysql.connector
from mysql.connector import Error


def get_db_config():
    """Get database configuration from environment variables."""
    config = {
        'host': os.getenv('DB_HOST', 'localhost'),
        'port': int(os.getenv('DB_PORT', 3306)),
        'user': os.getenv('DB_USERNAME'),
        'password': os.getenv('DB_PASSWORD'),
        'database': os.getenv('DB_NAME', 'testdb')
    }
    
    # Check for required environment variables
    if not config['user'] or not config['password']:
        print("Error: DB_USERNAME and DB_PASSWORD environment variables are required")
        sys.exit(1)
    
    return config


def create_connection(config):
    """Create a database connection."""
    try:
        connection = mysql.connector.connect(**config)
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


def insert_sample_data(connection):
    """Insert sample data into the messages table."""
    cursor = connection.cursor()
    
    # Sample data to insert
    messages_data = [
        ('2026-03-17', 'Welcome to our new messaging system!'),
        ('2026-03-16', 'Database connection established successfully.'),
        ('2026-03-15', 'System maintenance completed without issues.'),
        ('2026-03-14', 'New user registration feature deployed.'),
        ('2026-03-13', 'Performance optimization update applied.'),
        ('2026-03-12', 'Security patch installed and verified.'),
        ('2026-03-11', 'Backup process completed successfully.')
    ]
    
    insert_query = """
    INSERT INTO messages (created_at, message)
    VALUES (%s, %s)
    """
    
    try:
        cursor.executemany(insert_query, messages_data)
        connection.commit()
        print(f"Successfully inserted {cursor.rowcount} rows into messages table")
        
        # Display inserted data
        cursor.execute("SELECT * FROM messages ORDER BY id DESC LIMIT 7")
        rows = cursor.fetchall()
        
        print("\nRecently inserted messages:")
        print("-" * 80)
        print(f"{'ID':<5} {'Date':<12} {'Message':<60}")
        print("-" * 80)
        
        for row in rows:
            print(f"{row[0]:<5} {row[1]:<12} {row[2]:<60}")
            
    except Error as e:
        print(f"Error inserting data: {e}")
        connection.rollback()
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
    if not connection:
        sys.exit(1)
    
    try:
        # Create sample table
        create_sample_table(connection)
        
        # Insert sample data
        insert_sample_data(connection)
        
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if connection.is_connected():
            connection.close()
            print("\nMySQL connection closed")


if __name__ == "__main__":
    main()