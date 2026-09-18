using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class MovimientoCaja
    {
        public int Id { get; set; }
        public string Tipo { get; set; }
        public string Concepto { get; set; }
        public decimal Monto { get; set; }
        public string Descripcion { get; set; }
        public int IdUsuario { get; set; }

        private string connectionstring = Config.Conexion;

        // Registra un movimiento manual
        public void Registrar()
        {
            string sqlSentencia = "SP_MovimientoCaja_Registrar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Tipo", SqlDbType.NVarChar, 10).Value = Tipo;
            sqlCom.Parameters.Add("@Concepto", SqlDbType.NVarChar, 60).Value = Concepto;
            sqlCom.Parameters.Add("@Monto", SqlDbType.Decimal).Value = Monto;
            sqlCom.Parameters.Add("@Descripcion", SqlDbType.NVarChar, 250).Value =
                (object)Descripcion ?? System.DBNull.Value;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Lista los ultimos 200 movimientos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_MovimientoCaja_GetAll";
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

        // Saldo actual + totales del dia
        public DataTable ObtenerSaldo()
        {
            string sqlSentencia = "SP_MovimientoCaja_Saldo";
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