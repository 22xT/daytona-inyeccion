using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Text;

namespace WebApi.Models
{
    // Matcher, entregable 1 (script 86): etiquetado del benchmark
    public class Matcher
    {
        private string connectionstring = Config.Conexion;

        private DataSet Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 120;
                if (parametros != null) parametros(cmd);
                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd))
                {
                    cnn.Open();
                    da.Fill(ds);
                }
                return ds;
            }
        }

        private static DataTable Tabla(DataSet ds, int i)
        {
            return ds.Tables.Count > i ? ds.Tables[i] : new DataTable();
        }

        public DataTable Tipos()
        {
            return Tabla(Ejecutar("SP_Matcher_Tipos", null), 0);
        }

        public DataSet Ancla(string tipo, int? idAncla)
        {
            return Ejecutar("SP_Matcher_Ancla", c =>
            {
                c.Parameters.Add("@Tipo", SqlDbType.VarChar, 120).Value = string.IsNullOrWhiteSpace(tipo) ? (object)DBNull.Value : tipo.Trim();
                c.Parameters.Add("@IdAncla", SqlDbType.Int).Value = idAncla.HasValue ? (object)idAncla.Value : DBNull.Value;
            });
        }

        // Candidatos: la misma busqueda del Buscador, sin anotarla en el registro de busquedas
        public DataTable Candidatos(string texto)
        {
            DataSet ds = new Busqueda().Universal(texto, 0, false, 200);
            return Tabla(ds, 1);
        }

        public class ParDto { public int IdCandidato { get; set; } public string Relacion { get; set; } }

        public int Etiquetar(int idAncla, string estado, List<ParDto> pares, string nota, int idUsuario)
        {
            StringBuilder sb = new StringBuilder();
            if (pares != null)
                foreach (ParDto p in pares)
                {
                    if (p == null || p.IdCandidato <= 0 || string.IsNullOrWhiteSpace(p.Relacion)) continue;
                    if (sb.Length > 0) sb.Append(',');
                    sb.Append(p.IdCandidato).Append(':').Append(p.Relacion.Trim().ToUpperInvariant());
                }
            DataSet ds = Ejecutar("SP_Matcher_Etiquetar", c =>
            {
                c.Parameters.Add("@IdAncla", SqlDbType.Int).Value = idAncla;
                c.Parameters.Add("@Estado", SqlDbType.VarChar, 12).Value = estado;
                c.Parameters.Add("@Pares", SqlDbType.VarChar, -1).Value = sb.ToString();
                c.Parameters.Add("@Nota", SqlDbType.NVarChar, 200).Value = string.IsNullOrWhiteSpace(nota) ? (object)DBNull.Value : nota.Trim();
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario > 0 ? (object)idUsuario : DBNull.Value;
            });
            DataTable t = Tabla(ds, 0);
            return t.Rows.Count > 0 ? Convert.ToInt32(t.Rows[0][0]) : 0;
        }

        public DataTable ParesCodigo()
        {
            return Tabla(Ejecutar("SP_Matcher_ParesCodigo", null), 0);
        }

        public void RevisarCodigo(int idPar, string relacion, int idUsuario)
        {
            Ejecutar("SP_Matcher_RevisarCodigo", c =>
            {
                c.Parameters.Add("@IdPar", SqlDbType.Int).Value = idPar;
                c.Parameters.Add("@Relacion", SqlDbType.VarChar, 12).Value = relacion;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario > 0 ? (object)idUsuario : DBNull.Value;
            });
        }

        public DataSet Resumen()
        {
            return Ejecutar("SP_Matcher_Resumen", null);
        }
    }
}
