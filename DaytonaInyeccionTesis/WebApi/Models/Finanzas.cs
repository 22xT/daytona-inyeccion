using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Etapa 1 de Caja y Finanzas: adjuntos, gastos y movimientos
       especiales. Van juntos porque comparten el adjunto y el registro
       de dinero en cuentas. */

    public class Adjunto
    {
        private string connectionstring = Config.Conexion;

        public int Guardar(string nombre, string mime, byte[] contenido, int idUsuario)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Adjunto_I", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@NombreArchivo", SqlDbType.NVarChar, 200).Value = nombre;
                cmd.Parameters.Add("@TipoMime", SqlDbType.VarChar, 60).Value = mime;
                cmd.Parameters.Add("@Contenido", SqlDbType.VarBinary, -1).Value = contenido;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                cnn.Open();
                return Convert.ToInt32(cmd.ExecuteScalar());
            }
        }

        // Devuelve null si no existe
        public Tuple<string, string, byte[]> Obtener(int id)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Adjunto_Get", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                cnn.Open();
                using (SqlDataReader dr = cmd.ExecuteReader())
                {
                    if (!dr.Read()) return null;
                    return Tuple.Create(
                        Convert.ToString(dr["NombreArchivo"]),
                        Convert.ToString(dr["TipoMime"]),
                        (byte[])dr["Contenido"]);
                }
            }
        }
    }

    public class Gasto
    {
        private string connectionstring = Config.Conexion;

        public int IdTipoGasto { get; set; }
        public int? IdProveedor { get; set; }
        public string Emisor { get; set; }
        public DateTime Fecha { get; set; }
        public string Descripcion { get; set; }
        public decimal Importe { get; set; }
        public string TipoComprobante { get; set; }
        public string NumeroComprobante { get; set; }
        public int? IdAdjunto { get; set; }
        // Si viene, se registra y se paga en el mismo acto
        public int? IdCuentaPago { get; set; }

        private static object N(object v) { return v ?? DBNull.Value; }

        public DataTable Tipos()
        {
            return Consultar("SP_TipoGasto_GetAll", c => { });
        }

        public DataTable Listar(DateTime? desde, DateTime? hasta, string estado)
        {
            return Consultar("SP_Gasto_GetAll", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
                c.Parameters.Add("@Estado", SqlDbType.VarChar, 10).Value = N(string.IsNullOrWhiteSpace(estado) ? null : estado);
            });
        }

        public DataTable Resumen(DateTime? desde, DateTime? hasta)
        {
            return Consultar("SP_Gasto_Resumen", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
            });
        }

        public DataTable Registrar(int idUsuario)
        {
            return Consultar("SP_Gasto_I", c =>
            {
                c.Parameters.Add("@IdTipoGasto", SqlDbType.Int).Value = IdTipoGasto;
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = N(IdProveedor);
                c.Parameters.Add("@Emisor", SqlDbType.NVarChar, 100).Value = N(Emisor);
                c.Parameters.Add("@Fecha", SqlDbType.Date).Value = Fecha;
                c.Parameters.Add("@Descripcion", SqlDbType.NVarChar, 250).Value = N(Descripcion);
                c.Parameters.Add("@Importe", SqlDbType.Decimal).Value = Importe;
                c.Parameters.Add("@TipoComprobante", SqlDbType.VarChar, 20).Value = N(TipoComprobante);
                c.Parameters.Add("@NumeroComprobante", SqlDbType.VarChar, 40).Value = N(NumeroComprobante);
                c.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = N(IdAdjunto);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                c.Parameters.Add("@IdCuentaPago", SqlDbType.Int).Value = N(IdCuentaPago);
            });
        }

        public void Pagar(int idGasto, int idCuenta, int idUsuario)
        {
            Ejecutar("SP_Gasto_Pagar", c =>
            {
                c.Parameters.Add("@IdGasto", SqlDbType.Int).Value = idGasto;
                c.Parameters.Add("@IdCuentaFinanciera", SqlDbType.Int).Value = idCuenta;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public void AnularPago(int idGasto, string motivo, int idUsuario)
        {
            Ejecutar("SP_Gasto_AnularPago", c =>
            {
                c.Parameters.Add("@IdGasto", SqlDbType.Int).Value = idGasto;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public void Anular(int idGasto, string motivo, int idUsuario)
        {
            Ejecutar("SP_Gasto_Anular", c =>
            {
                c.Parameters.Add("@IdGasto", SqlDbType.Int).Value = idGasto;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        private DataTable Consultar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                DataTable dt = new DataTable();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd)) { da.Fill(dt); }
                return dt;
            }
        }

        private void Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                cnn.Open();
                cmd.ExecuteNonQuery();
            }
        }
    }

    public class MovimientoEspecial
    {
        private string connectionstring = Config.Conexion;

        public string Tipo { get; set; }             // APORTE, RETIRO, TRANSFERENCIA, AJUSTE
        public int? IdCuentaOrigen { get; set; }
        public int? IdCuentaDestino { get; set; }
        public decimal Importe { get; set; }
        public string Motivo { get; set; }
        public int? IdAdjunto { get; set; }

        private static object N(object v) { return v ?? DBNull.Value; }

        public int Registrar(int idUsuario)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_MovimientoEspecial_I", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Tipo", SqlDbType.VarChar, 15).Value = N(Tipo);
                cmd.Parameters.Add("@IdCuentaOrigen", SqlDbType.Int).Value = N(IdCuentaOrigen);
                cmd.Parameters.Add("@IdCuentaDestino", SqlDbType.Int).Value = N(IdCuentaDestino);
                cmd.Parameters.Add("@Importe", SqlDbType.Decimal).Value = Importe;
                cmd.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(Motivo);
                cmd.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = N(IdAdjunto);
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                cnn.Open();
                return Convert.ToInt32(cmd.ExecuteScalar());
            }
        }

        public void Anular(int id, string motivo, int idUsuario)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_MovimientoEspecial_Anular", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                cmd.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                cnn.Open();
                cmd.ExecuteNonQuery();
            }
        }

        public DataTable Listar(DateTime? desde, DateTime? hasta)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_MovimientoEspecial_GetAll", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                cmd.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
                DataTable dt = new DataTable();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd)) { da.Fill(dt); }
                return dt;
            }
        }

        public DataTable CuentasDisponibles()
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_CuentaFinanciera_GetAll", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                DataTable dt = new DataTable();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd)) { da.Fill(dt); }
                return dt;
            }
        }
    }
}
