using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    // Apertura, arqueo y cierre de la caja fisica
    public class SesionCaja
    {
        private string connectionstring = Config.Conexion;

        private static object N(object v) { return v ?? DBNull.Value; }

        public DataTable Actual()
        {
            return Consultar("SP_SesionCaja_Actual", c => { });
        }

        public DataTable Abrir(decimal saldoInicial, string motivo, int idUsuario)
        {
            return Consultar("SP_SesionCaja_Abrir", c =>
            {
                c.Parameters.Add("@SaldoInicial", SqlDbType.Decimal).Value = saldoInicial;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public DataTable Cerrar(decimal efectivoContado, string motivo, int idUsuario)
        {
            return Consultar("SP_SesionCaja_Cerrar", c =>
            {
                c.Parameters.Add("@EfectivoContado", SqlDbType.Decimal).Value = efectivoContado;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public DataTable Historial(DateTime? desde, DateTime? hasta)
        {
            return Consultar("SP_SesionCaja_Historial", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
            });
        }

        public DataTable ResumenDiferencias(DateTime? desde, DateTime? hasta)
        {
            return Consultar("SP_SesionCaja_ResumenDiferencias", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
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
    }
}
