using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    // Auditoria general (script 83): quien cambio que y cuando
    public class Auditoria
    {
        private string connectionstring = Config.Conexion;

        public DataSet Listar(DateTime desde, DateTime hasta, int? idUsuario, string tipo, string texto, int max)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Auditoria_Listar", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 60;
                cmd.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.Date;
                cmd.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.Date;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario.HasValue ? (object)idUsuario.Value : DBNull.Value;
                cmd.Parameters.Add("@Tipo", SqlDbType.VarChar, 20).Value = string.IsNullOrWhiteSpace(tipo) ? (object)DBNull.Value : tipo.Trim();
                cmd.Parameters.Add("@Texto", SqlDbType.NVarChar, 100).Value = string.IsNullOrWhiteSpace(texto) ? (object)DBNull.Value : texto.Trim();
                cmd.Parameters.Add("@Max", SqlDbType.Int).Value = max;

                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    cnn.Open();
                    da.Fill(ds);
                }
                string[] nombres = { "Renglones", "PorTipo", "PorUsuario" };
                for (int i = 0; i < ds.Tables.Count && i < nombres.Length; i++)
                    ds.Tables[i].TableName = nombres[i];
                return ds;
            }
        }
    }
}
