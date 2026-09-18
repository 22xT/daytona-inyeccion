using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class ReporteStockCritico
    {
        private string connectionstring = Config.Conexion;

        public DataTable Obtener()
        {
            string sqlSentencia = "SP_Reporte_StockCritico";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;

            SqlDataAdapter adapter = new SqlDataAdapter(sqlCom);
            DataTable tabla = new DataTable();
            sqlCnn.Open();
            adapter.Fill(tabla);
            sqlCnn.Close();
            return tabla;
        }
    }
}