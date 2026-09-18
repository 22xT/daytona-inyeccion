using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Pedido
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public DateTime Fecha { get; set; }
        public int IdProveedor { get; set; }
        public decimal Total { get; set; }
        public int IdEstado { get; set; }

        // Listar todos los pedidos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Pedido_GetAll";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

       
        public DataSet ListarPorId()
        {
            string sqlSentencia = "SP_Pedido_GetId";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds;
        }

        public int Guardar()
        {
            string sqlSentencia = "SP_Pedido_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = IdProveedor;
            sqlCom.Parameters.Add("@Total", SqlDbType.Decimal).Value = Total;

            sqlCnn.Open();
            object resultado = sqlCom.ExecuteScalar();
            sqlCnn.Close();

            return Convert.ToInt32(resultado);
        }

        public void Editar(int idUsuario = 0)
        {
            string sqlSentencia = "SP_Pedido_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@IdEstado", SqlDbType.Int).Value = IdEstado;
            sqlCom.Parameters.Add("@Total", SqlDbType.Decimal).Value = Total;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario == 0 ? (object)DBNull.Value : idUsuario;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Eliminar()
        {
            string sqlSentencia = "SP_Pedido_D";
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