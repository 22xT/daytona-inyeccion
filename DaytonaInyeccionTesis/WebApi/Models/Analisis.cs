using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    // Reportes analiticos: pronostico, punto de equilibrio y comparacion
    // de periodos. Van aparte de Reporte.cs para no mezclar con los
    // listados existentes.
    public class Analisis
    {
        private string connectionstring = Config.Conexion;

        public DataTable Pronostico(int mesesHistoria, int mesesProyectar)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_Reporte_Pronostico", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@MesesHistoria", SqlDbType.Int).Value = mesesHistoria;
            sqlCom.Parameters.Add("@MesesProyectar", SqlDbType.Int).Value = mesesProyectar;
            return Ejecutar(sqlCnn, sqlCom);
        }

        public DataTable PuntoEquilibrio(DateTime? desde, DateTime? hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_Reporte_PuntoEquilibrio", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value : DBNull.Value;
            return Ejecutar(sqlCnn, sqlCom);
        }

        public DataTable Periodo(DateTime? desde, DateTime? hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_Dashboard_Periodo", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value : DBNull.Value;
            return Ejecutar(sqlCnn, sqlCom);
        }

        public DataTable MapaCalor(DateTime? desde, DateTime? hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_Dashboard_MapaCalor", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value : DBNull.Value;
            return Ejecutar(sqlCnn, sqlCom);
        }

        private DataTable Ejecutar(SqlConnection cnn, SqlCommand cmd)
        {
            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = cmd;
            DataSet ds = new DataSet();
            cnn.Open();
            da.Fill(ds);
            cnn.Close();
            return ds.Tables[0];
        }
    }
}
