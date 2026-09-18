using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class MovimientoStock
    {
        // Propiedades
        public int Id { get; set; }
        public int IdRepuesto { get; set; }
        public int CantidadNueva { get; set; }
        public string Tipo { get; set; }
        public string Motivo { get; set; }
        public int IdUsuario { get; set; }

        private string connectionstring = Config.Conexion;

        // Ejecuta el ajuste de stock (actualiza Stock + registra movimiento)
        public void Ajustar()
        {
            string sqlSentencia = "SP_MovimientoStock_Ajustar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = IdRepuesto;
            sqlCom.Parameters.Add("@CantidadNueva", SqlDbType.Int).Value = CantidadNueva;
            sqlCom.Parameters.Add("@Tipo", SqlDbType.NVarChar, 40).Value = Tipo;
            sqlCom.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = Motivo;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Historial completo (ultimos 200)
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_MovimientoStock_GetAll";
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

        // Historial de un repuesto
        public DataTable ListarPorRepuesto()
        {
            string sqlSentencia = "SP_MovimientoStock_GetByRepuesto";
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