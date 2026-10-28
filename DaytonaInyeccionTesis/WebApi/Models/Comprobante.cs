using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Comprobantes fiscales (script 92): factura, nota de credito y nota
       de debito de cada venta o nota. En la fase 1 quedan en BORRADOR;
       en la fase 2 se piden los CAE a ARCA. */
    public class Comprobante
    {
        private string connectionstring = Config.Conexion;

        // Factura de una venta. Si ya la tiene devuelve la misma.
        public DataTable DesdeVenta(int idVenta, int idUsuario)
        {
            return Ejecutar("SP_Comprobante_DesdeVenta", cmd =>
            {
                cmd.Parameters.Add("@IdVenta", SqlDbType.Int).Value = idVenta;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        // NC o ND de una nota de cliente. Si ya la tiene devuelve la misma.
        public DataTable DesdeNota(int idNota, int idUsuario)
        {
            return Ejecutar("SP_Comprobante_DesdeNota", cmd =>
            {
                cmd.Parameters.Add("@IdNota", SqlDbType.Int).Value = idNota;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        // Antes de anular una venta (soloValidar) y despues, para anular su borrador
        public void AnularDeVenta(int idVenta, int idUsuario, bool soloValidar)
        {
            Ejecutar("SP_Comprobante_AnularDeVenta", cmd =>
            {
                cmd.Parameters.Add("@IdVenta", SqlDbType.Int).Value = idVenta;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
                cmd.Parameters.Add("@SoloValidar", SqlDbType.Bit).Value = soloValidar;
            });
        }

        public DataTable Listar(DateTime? desde, DateTime? hasta, string estado, string clase)
        {
            return Ejecutar("SP_Comprobante_GetAll", cmd =>
            {
                cmd.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value.Date : DBNull.Value;
                cmd.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value.Date : DBNull.Value;
                cmd.Parameters.Add("@Estado", SqlDbType.VarChar, 10).Value = string.IsNullOrWhiteSpace(estado) ? (object)DBNull.Value : estado.Trim().ToUpper();
                cmd.Parameters.Add("@Clase", SqlDbType.Char, 2).Value = string.IsNullOrWhiteSpace(clase) ? (object)DBNull.Value : clase.Trim().ToUpper();
            }).Tables[0];
        }

        // Cabecera, renglones, IVA por alicuota y notas que la corrigen
        public DataSet Obtener(int id)
        {
            return Ejecutar("SP_Comprobante_GetId", cmd =>
            {
                cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
            });
        }

        public DataTable Emisor()
        {
            return Ejecutar("SP_Emisor_Get", cmd => { }).Tables[0];
        }

        // Anula un borrador o rechazado y genera uno nuevo con los datos actuales del cliente
        public DataTable Rehacer(int id, int idUsuario)
        {
            DataSet ds = Ejecutar("SP_Comprobante_Rehacer", cmd =>
            {
                cmd.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
            return ds.Tables.Count > 0 ? ds.Tables[ds.Tables.Count - 1] : null;
        }

        public DataTable HistorialArca(int idComprobante)
        {
            return Ejecutar("SP_ArcaSolicitud_GetByComprobante", cmd =>
            {
                cmd.Parameters.Add("@IdComprobante", SqlDbType.Int).Value = idComprobante;
            }).Tables[0];
        }

        public DataTable Pendientes()
        {
            return Ejecutar("SP_Comprobante_Pendientes", cmd => { }).Tables[0];
        }

        private DataSet Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    cnn.Open();
                    da.Fill(ds);
                }
                return ds;
            }
        }

        /* Lo usan la venta y las notas despues de registrarse: si el
           comprobante no se pudo generar, la operacion ya quedo hecha y
           se devuelve el aviso para mostrarlo (queda en Pendientes). */
        public static object IntentarDesdeVenta(int idVenta, int idUsuario)
        {
            try
            {
                DataTable dt = new Comprobante().DesdeVenta(idVenta, idUsuario);
                return Resultado(dt, null);
            }
            catch (SqlException ex)
            {
                return Resultado(null, ex.Number >= 50000 ? ex.Message : "No se pudo generar el comprobante.");
            }
            catch (Exception)
            {
                // La operacion ya quedo registrada: nunca se la hace fallar por esto
                return Resultado(null, null);
            }
        }

        public static object IntentarDesdeNota(int idNota, int idUsuario)
        {
            try
            {
                DataTable dt = new Comprobante().DesdeNota(idNota, idUsuario);
                return Resultado(dt, null);
            }
            catch (SqlException ex)
            {
                return Resultado(null, ex.Number >= 50000 ? ex.Message : "No se pudo generar el comprobante.");
            }
            catch (Exception)
            {
                // La operacion ya quedo registrada: nunca se la hace fallar por esto
                return Resultado(null, null);
            }
        }

        private static object Resultado(DataTable dt, string aviso)
        {
            if (dt == null || dt.Rows.Count == 0)
                return new { IdComprobante = (int?)null, Tipo = (string)null, Estado = (string)null,
                             Aviso = aviso ?? "No se pudo generar el comprobante." };
            DataRow r = dt.Rows[0];
            return new
            {
                IdComprobante = (int?)Convert.ToInt32(r["IdComprobante"]),
                Tipo = Convert.ToString(r["Tipo"]),
                Estado = Convert.ToString(r["Estado"]),
                Aviso = (string)null
            };
        }
    }
}
