# utils/db_utils.py
"""
Database Utilities - Centralized database access
"""

import os
from pymongo import MongoClient
import certifi

# Global db instance (set by backend.py)
_db_instance = None
_client_instance = None


def set_db(db_instance):
    """Set the global database instance"""
    global _db_instance
    _db_instance = db_instance


def set_client(client_instance):
    """Set the global client instance"""
    global _client_instance
    _client_instance = client_instance


def get_db():
    """Get the global database instance"""
    if _db_instance is None:
        # Try to initialize if not set
        initialize_mongodb()
    return _db_instance


def get_client():
    """Get the global client instance"""
    return _client_instance


def initialize_mongodb():
    """Initialize MongoDB connection"""
    global _db_instance, _client_instance
    
    MONGO_URL = os.environ.get(
        "MONGO_URL",
        "mongodb://localhost:27017/student_management"
    )
    
    try:
        print(f"🔗 Attempting MongoDB connection...")
        
        connection_options = {
            'tls': True,
            'tlsCAFile': certifi.where(),
            'connectTimeoutMS': 10000,
            'socketTimeoutMS': 30000,
            'serverSelectionTimeoutMS': 15000,
            'retryWrites': True,
            'maxPoolSize': 50
        }
        
        _client_instance = MongoClient(MONGO_URL, **connection_options)
        _client_instance.admin.command('ping')
        _db_instance = _client_instance["student_management"]
        print("✅ MongoDB connected successfully!")
        return True
        
    except Exception as e:
        print(f"❌ MongoDB connection failed: {e}")
        _db_instance = None
        _client_instance = None
        return False