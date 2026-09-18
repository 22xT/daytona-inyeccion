using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class ReporteVentas
    {
        private string connectionstring = Config.Conexion;

        public DataTable Resumen(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Reporte_VentasResumen", desde, hasta);
        }

        public DataTable PorDia(DateTime desde, DateTime hasta)
        {
            return Ejecutar("SP_Reporte_VentasPeriodo", desde, hasta);
        }

        private DataTable Ejecutar(string sp, DateTime desde, DateTime hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sp, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta;

            SqlDataAdapter adapter = new SqlDataAdapter(sqlCom);
            DataTable tabla = new DataTable();
            sqlCnn.Open();
            adapter.Fill(tabla);
            sqlCnn.Close();
            return tabla;
        }
    }
}