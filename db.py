import pyodbc

SERVER = "localhost,1433"
DATABASE = "MiniEcommerce"
USERNAME = "sa"
PASSWORD = "SqlServer@2026!"  # <-- la de Docker

CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={SERVER};"
    f"DATABASE={DATABASE};"
    f"UID={USERNAME};"
    f"PWD={PASSWORD};"
    "TrustServerCertificate=yes;"
    "Encrypt=no;"
)

def get_conn():
    return pyodbc.connect(CONN_STR)