using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Notificacion
    {
        private string connectionstring = Config.Conexion;

        // Ventas anuladas en las ultimas 24hs
        public DataTable VentasAnuladasRecientes()
        {
            string sql = @"
                SELECT TOP 10
                    v.Id,
                    v.Fecha,
                    v.Total,
                    c.Nombre + ' ' + c.Apellido AS Cliente,
                    ua.Nombre                   AS AnuladoPor,
                    v.FechaAnulacion
                FROM Venta v
                INNER JOIN Cliente c   ON c.Id  = v.IdCliente
                LEFT  JOIN Usuario ua  ON ua.Id = v.IdUsuarioAnulacion
                WHERE v.IdEstadoVenta = 2
                  AND v.FechaAnulacion >= DATEADD(HOUR, -24, GETDATE())
                ORDER BY v.FechaAnulacion DESC;";

            return EjecutarConsulta(sql);
        }

        // Pedidos cancelados en las ultimas 24hs
        public DataTable PedidosCanceladosRecientes()
        {
            string sql = @"
                SELECT TOP 10
                    p.Id,
                    p.Fecha,
                    p.Total,
                    pr.RazonSocial              AS Proveedor,
                    uc.Nombre                   AS CanceladoPor,
                    p.FechaCancelacion
                FROM Pedido p
                INNER JOIN Proveedor pr ON pr.Id = p.IdProveedor
                LEFT  JOIN Usuario uc   ON uc.Id = p.IdUsuarioCancelacion
                WHERE p.IdEstado = 3
                  AND p.FechaCancelacion >= DATEADD(HOUR, -24, GETDATE())
                ORDER BY p.FechaCancelacion DESC;";

            return EjecutarConsulta(sql);
        }

        // Cantidad de solicitudes de reset pendientes
        public int SolicitudesResetPendientes()
        {
            string sql = "SELECT COUNT(*) FROM SolicitudReset WHERE Estado = 'Pendiente';";
            return EjecutarScalar(sql);
        }

        // Cantidad de repuestos en stock critico (debajo del minimo)
        public int RepuestosStockCritico()
        {
            string sql = @"
                SELECT COUNT(*) 
                FROM Stock s
                INNER JOIN Repuesto r ON r.Id = s.IdRepuesto
                WHERE r.Activo = 1 
                  AND s.Cantidad <= s.StockMinimo;";
            return EjecutarScalar(sql);
        }
        // Ajustes de stock en las ultimas 24hs
        public DataTable AjustesStockRecientes()
        {
            string sql = @"
                SELECT TOP 10
                    m.Id,
                    m.IdRepuesto,
                    r.Descripcion               AS Repuesto,
                    r.Codigo                    AS CodigoRepuesto,
                    m.CantidadAnterior,
                    m.CantidadNueva,
                    m.Diferencia,
                    m.Tipo,
                    m.Motivo,
                    u.Nombre                    AS AjustadoPor,
                    m.Fecha
                FROM MovimientoStock m
                INNER JOIN Repuesto r ON r.Id = m.IdRepuesto
                INNER JOIN Usuario u  ON u.Id = m.IdUsuario
                WHERE m.Fecha >= DATEADD(HOUR, -24, GETDATE())
                ORDER BY m.Fecha DESC;";
            return EjecutarConsulta(sql);
        }

        // Ejecuta una consulta SELECT y devuelve un DataTable
        private DataTable EjecutarConsulta(string sql)
        {
            DataTable tabla = new DataTable();
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sql, cnn))
            using (SqlDataAdapter adapter = new SqlDataAdapter(cmd))
            {
                cnn.Open();
                adapter.Fill(tabla);
            }
            return tabla;
        }

        // Ejecuta una consulta que devuelve un solo valor (COUNT)
        private int EjecutarScalar(string sql)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sql, cnn))
            {
                cnn.Open();
                object res = cmd.ExecuteScalar();
                return res == null ? 0 : System.Convert.ToInt32(res);
            }
        }
    }
}