from db import get_conn

conn = get_conn()
cur = conn.cursor()
cur.execute("SELECT TOP 1 Email, Rol FROM dbo.Usuarios ORDER BY UsuarioID")
print(cur.fetchone())
cur.close()
conn.close()
print("Conexión OK ✅")