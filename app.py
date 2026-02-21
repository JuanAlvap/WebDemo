from flask import Flask, render_template, request, redirect, url_for, session, flash
from functools import wraps
from db import get_conn
import time

app = Flask(__name__)
app.secret_key = "demo_secret_key_change_me"

# ----------------------------
# "Base de datos" temporal en memoria (luego la cambiamos a SQL Server)
# ----------------------------

PRODUCTS = [
    {"id": 1, "name": "Teclado Mecánico", "price": 220000, "stock": 10},
    {"id": 2, "name": "Mouse Gamer", "price": 120000, "stock": 8},
    {"id": 3, "name": "SSD 1TB", "price": 350000, "stock": 3},
]

ORDERS = []  # cada orden: {email, items, total, ts}


# ----------------------------
# Helpers de auth
# ----------------------------
def login_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return wrapper


def role_required(role):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            if "user" not in session:
                return redirect(url_for("login"))
            if session["user"]["role"] != role:
                flash("No tienes permiso para ver esa página.", "danger")
                return redirect(url_for("shop"))
            return f(*args, **kwargs)
        return wrapper
    return decorator


def find_product(pid: int):
    for p in PRODUCTS:
        if p["id"] == pid:
            return p
    return None


# ----------------------------
# Rutas
# ----------------------------
@app.route("/")
def home():
    if "user" in session:
        return redirect(url_for("shop"))
    return redirect(url_for("login"))


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        name = request.form.get("name", "").strip()
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "").strip()

        if not name or not email or not password:
            flash("Completa todos los campos.", "danger")
            return redirect(url_for("register"))

        try:
            conn = get_conn()
            cur = conn.cursor()

            # Verificar si existe
            cur.execute("SELECT COUNT(*) FROM dbo.Usuarios WHERE Email = ?", (email,))
            if cur.fetchone()[0] > 0:
                cur.close()
                conn.close()
                flash("Ese email ya está registrado.", "danger")
                return redirect(url_for("register"))

            # Insertar usuario normal
            cur.execute(
                "INSERT INTO dbo.Usuarios (Nombre, Email, Pass, Rol) VALUES (?, ?, ?, 'user')",
                (name, email, password),
            )
            conn.commit()
            cur.close()
            conn.close()

            flash("Registro exitoso. Ahora inicia sesión.", "success")
            return redirect(url_for("login"))

        except Exception as e:
            flash(f"Error registrando usuario: {str(e)}", "danger")
            return redirect(url_for("register"))

    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "").strip()

        try:
            conn = get_conn()
            cur = conn.cursor()

            cur.execute(
                "SELECT Nombre, Email, Rol FROM dbo.Usuarios WHERE Email = ? AND Pass = ?",
                (email, password),
            )
            row = cur.fetchone()
            cur.close()
            conn.close()

            if not row:
                flash("Credenciales incorrectas.", "danger")
                return redirect(url_for("login"))

            session["user"] = {"name": row[0], "email": row[1], "role": row[2]}
            flash(f"Bienvenido, {row[0]} ✅", "success")
            return redirect(url_for("shop"))

        except Exception as e:
            flash(f"Error en login: {str(e)}", "danger")
            return redirect(url_for("login"))

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("Sesión cerrada.", "success")
    return redirect(url_for("login"))


@app.route("/shop")
@login_required
def shop():
    products = fetchall_dict("""
        SELECT ProductoID, Nombre, Precio, Stock
        FROM dbo.Productos
        ORDER BY ProductoID;
    """)
    return render_template("shop.html", products=products, user=session["user"])


@app.route("/buy", methods=["POST"])
@login_required
def buy():
    print("FORM:", dict(request.form))  # <-- mira esto en la consola

    pid_raw = request.form.get("product_id")
    qty_raw = request.form.get("qty")

    if pid_raw is None or qty_raw is None:
        flash(f"Formulario incompleto. Recibí: {dict(request.form)}", "danger")
        return redirect(url_for("shop"))

    try:
        pid = int(pid_raw)
        qty = int(qty_raw)
    except Exception:
        flash(f"Valores inválidos. product_id={pid_raw}, qty={qty_raw}", "danger")
        return redirect(url_for("shop"))

    if qty <= 0:
        flash("Cantidad inválida.", "danger")
        return redirect(url_for("shop"))

    conn = get_conn()
    try:
        cur = conn.cursor()

        cur.execute("SELECT UsuarioID FROM dbo.Usuarios WHERE Email = ?", (session["user"]["email"],))
        row_u = cur.fetchone()
        if not row_u:
            flash("Usuario no existe en BD.", "danger")
            return redirect(url_for("shop"))
        usuario_id = row_u[0]

        cur.execute("SELECT Nombre, Precio, Stock FROM dbo.Productos WHERE ProductoID = ?", (pid,))
        row_p = cur.fetchone()
        if not row_p:
            flash("Producto no existe.", "danger")
            return redirect(url_for("shop"))

        nombre, precio, stock = row_p
        if stock < qty:
            flash(f"Stock insuficiente. Disponible: {stock}", "danger")
            return redirect(url_for("shop"))

        total = float(precio) * qty

        cur.execute("""
            INSERT INTO dbo.Ordenes (UsuarioID, Total) 
            OUTPUT inserted.OrdenID
            VALUES (?, ?)
        """, (usuario_id, total))
        orden_id = int(cur.fetchone()[0])

        cur.execute("""
            INSERT INTO dbo.DetalleOrden (OrdenID, ProductoID, Cantidad, PrecioUnit)
            VALUES (?, ?, ?, ?)
        """, (orden_id, pid, qty, precio))

        cur.execute("UPDATE dbo.Productos SET Stock = Stock - ? WHERE ProductoID = ?", (qty, pid))

        conn.commit()
        flash(f"Compra realizada ✅ ({nombre} x{qty})", "success")
        return redirect(url_for("shop"))

    except Exception as e:
        conn.rollback()
        flash(f"Error comprando: {str(e)}", "danger")
        return redirect(url_for("shop"))
    finally:
        conn.close()

def fetchall_dict(query, params=None):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(query, params or [])
    cols = [c[0] for c in cur.description]
    rows = [dict(zip(cols, row)) for row in cur.fetchall()]
    cur.close()
    conn.close()
    return rows

def execute_sql(query, params=None):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute(query, params or [])
    conn.commit()
    cur.close()
    conn.close()

@app.route("/admin")
@role_required("admin")
def admin():
    mode = request.args.get("mode", "htap")  # htap o olap

    if mode == "olap":
        # Lee la tabla resumen (batch)
        rows = fetchall_dict("""
            SELECT ProductoID, Nombre, Unidades, IngresoTotal, UltimaActualizacion
            FROM dbo.ReporteVentasProducto
            ORDER BY IngresoTotal DESC;
        """)
        last_update = rows[0]["UltimaActualizacion"] if rows else None
        return render_template("admin.html",
                               mode=mode, rows=rows, last_update=last_update,
                               user=session["user"])
    else:
        # HTAP: calcula EN VIVO desde OLTP (sin depender de ETL)
        rows = fetchall_dict("""
            SELECT
                p.ProductoID,
                p.Nombre,
                COALESCE(SUM(d.Cantidad), 0) AS Unidades,
                COALESCE(SUM(d.Cantidad * d.PrecioUnit), 0) AS IngresoTotal
            FROM dbo.Productos p
            LEFT JOIN dbo.DetalleOrden d ON d.ProductoID = p.ProductoID
            LEFT JOIN dbo.Ordenes o ON o.OrdenID = d.OrdenID
            GROUP BY p.ProductoID, p.Nombre
            ORDER BY IngresoTotal DESC;
        """)
        return render_template("admin.html",
                               mode=mode, rows=rows, last_update=None,
                               user=session["user"])
    
@app.route("/admin/refresh_olap", methods=["POST"])
@role_required("admin")
def refresh_olap():
    try:
        execute_sql("EXEC dbo.sp_ActualizarReporteVentasProducto;")
        flash("OLAP actualizado (ETL ejecutado) ✅", "success")
    except Exception as e:
        flash(f"Error actualizando OLAP: {str(e)}", "danger")
    return redirect(url_for("admin", mode="olap"))


if __name__ == "__main__":
    app.run(debug=True)