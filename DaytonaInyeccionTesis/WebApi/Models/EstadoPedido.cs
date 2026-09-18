using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class EstadoPedido
    {
        public int Id { get; set; }
        public string Nombre { get; set; }
        public bool Activo { get; set; }

        private string connectionstring = Config.Conexion;

        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_EstadoPedido_GetAll";
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

        public DataTable ListarPorId()
        {
            string sqlSentencia = "SP_EstadoPedido_GetId";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            SqlDataAdapter adapter = new SqlDataAdapter(sqlCom);
            DataTable tabla = new DataTable();
            sqlCnn.Open();
            adapter.Fill(tabla);
            sqlCnn.Close();
            return tabla;
        }

        public void Guardar()
        {
            string sqlSentencia = "SP_EstadoPedido_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar, 50).Value = Nombre;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Editar()
        {
            string sqlSentencia = "SP_EstadoPedido_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar, 50).Value = Nombre;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Eliminar()
        {
            string sqlSentencia = "SP_EstadoPedido_D";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Activar()
        {
            string sqlSentencia = "SP_EstadoPedido_Activar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}