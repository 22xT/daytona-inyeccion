using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Stock
    {
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public int StockMinimo { get; set; }

        private string connectionstring = Config.Conexion;
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Stock_GetAll";
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

        public DataTable ListarPorRepuesto()
        {
            string sqlSentencia = "SP_Stock_GetByRepuesto";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = IdRepuesto;

            SqlDataAdapter adapter = new SqlDataAdapter(sqlCom);
            DataTable tabla = new DataTable();
            sqlCnn.Open();
            adapter.Fill(tabla);
            sqlCnn.Close();
            return tabla;
        }
    }
}