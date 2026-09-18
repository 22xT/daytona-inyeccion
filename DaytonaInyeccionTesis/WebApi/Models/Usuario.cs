using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Usuario
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public string Nombre { get; set; }
        public string Correo { get; set; }
        public string ClaveHash { get; set; }
        public int IdRol { get; set; }
        public string NombreRol { get; set; }
        public bool Activo { get; set; }
        public DateTime FechaAlta { get; set; }
        public DateTime? UltimoAcceso { get; set; }

        // Listar todos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Usuario_GetAll";
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
            string sqlSentencia = "SP_Usuario_GetById";
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
            string sqlSentencia = "SP_Usuario_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Correo", SqlDbType.NVarChar).Value = (object)Correo ?? DBNull.Value;
            sqlCom.Parameters.Add("@ClaveHash", SqlDbType.NVarChar).Value = (object)ClaveHash ?? DBNull.Value;
            sqlCom.Parameters.Add("@IdRol", SqlDbType.Int).Value = IdRol;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Actualizar
        public void Editar()
        {
            string sqlSentencia = "SP_Usuario_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Correo", SqlDbType.NVarChar).Value = (object)Correo ?? DBNull.Value;
            sqlCom.Parameters.Add("@ClaveHash", SqlDbType.NVarChar).Value = (object)ClaveHash ?? DBNull.Value;
            sqlCom.Parameters.Add("@IdRol", SqlDbType.Int).Value = IdRol;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Baja logica
        public void Eliminar()
        {
            string sqlSentencia = "SP_Usuario_D";
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
            string sqlSentencia = "SP_Usuario_Activar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Reset administrativo de contraseña.
        // El Controller debe hashear ClaveHash con BCrypt antes de invocar este metodo.
        public void ResetearClave()
        {
            string sqlSentencia = "SP_Usuario_ResetClave";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@ClaveHash", SqlDbType.NVarChar).Value = (object)ClaveHash ?? DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
        // Registra el ultimo login del usuario (lo llama el LoginController).
        public void RegistrarAcceso()
        {
            string sqlSentencia = "SP_Usuario_RegistrarAcceso";
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
