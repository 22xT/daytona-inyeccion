using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Rubro
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public string Nombre { get; set; }
        public string Sigla { get; set; }
        public bool Activo { get; set; }

        // Listar todos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Rubro_GetAll";
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

        // Listar uno por Id
        public DataTable ListarPorId()
        {
            string sqlSentencia = "SP_Rubro_GetId";
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

            return ds.Tables[0];
        }

        // Insertar
        public void Guardar()
        {
            string sqlSentencia = "SP_Rubro_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Sigla", SqlDbType.NVarChar).Value = (object)Sigla ?? DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Actualizar
        public void Editar()
        {
            string sqlSentencia = "SP_Rubro_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Sigla", SqlDbType.NVarChar).Value = (object)Sigla ?? DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Baja logica
        public void Eliminar()
        {
            string sqlSentencia = "SP_Rubro_D";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Reactivar
        public void Activar()
        {
            string sqlSentencia = "SP_Rubro_Activar";
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