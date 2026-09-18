using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Dashboard
    {
        private string connectionstring = Config.Conexion;

        public DataSet Obtener(DateTime desde, DateTime hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_Dashboard_General", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta;

            SqlDataAdapter adapter = new SqlDataAdapter(sqlCom);
            DataSet ds = new DataSet();
            sqlCnn.Open();
            adapter.Fill(ds);
            sqlCnn.Close();

            // Nombrar las tablas para que el JSON salga claro
            if (ds.Tables.Count >= 6)
            {
                ds.Tables[0].TableName = "Kpis";
                ds.Tables[1].TableName = "VentasPorDia";
                ds.Tables[2].TableName = "VentasPorRubro";
                ds.Tables[3].TableName = "TopProductos";
                ds.Tables[4].TableName = "CajaPorMes";
                ds.Tables[5].TableName = "MapaCalor";
            }

            return ds;
        }
    }
}