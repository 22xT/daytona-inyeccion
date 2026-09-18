using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Proveedor
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public string Cuit { get; set; }
        public string RazonSocial { get; set; }
        public string CondicionIva { get; set; }
        public string Calle { get; set; }
        public string Numero { get; set; }
        public string Barrio { get; set; }
        public string Localidad { get; set; }
        public string Provincia { get; set; }
        public string CodigoPostal { get; set; }
        public string Telefono { get; set; }
        public string Mail { get; set; }
        public string Observaciones { get; set; }
        public bool Activo { get; set; }

        // Listar todos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Proveedor_GetAll";
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
            string sqlSentencia = "SP_Proveedor_GetId";
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
            string sqlSentencia = "SP_Proveedor_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Cuit", SqlDbType.NVarChar).Value = (object)Cuit ?? DBNull.Value;
            sqlCom.Parameters.Add("@RazonSocial", SqlDbType.NVarChar).Value = (object)RazonSocial ?? DBNull.Value;
            sqlCom.Parameters.Add("@CondicionIva", SqlDbType.NVarChar).Value = (object)CondicionIva ?? DBNull.Value;
            sqlCom.Parameters.Add("@Calle", SqlDbType.NVarChar).Value = (object)Calle ?? DBNull.Value;
            sqlCom.Parameters.Add("@Numero", SqlDbType.NVarChar).Value = (object)Numero ?? DBNull.Value;
            sqlCom.Parameters.Add("@Barrio", SqlDbType.NVarChar).Value = (object)Barrio ?? DBNull.Value;
            sqlCom.Parameters.Add("@Localidad", SqlDbType.NVarChar).Value = (object)Localidad ?? DBNull.Value;
            sqlCom.Parameters.Add("@Provincia", SqlDbType.NVarChar).Value = (object)Provincia ?? DBNull.Value;
            sqlCom.Parameters.Add("@CodigoPostal", SqlDbType.NVarChar).Value = (object)CodigoPostal ?? DBNull.Value;
            sqlCom.Parameters.Add("@Telefono", SqlDbType.NVarChar).Value = (object)Telefono ?? DBNull.Value;
            sqlCom.Parameters.Add("@Mail", SqlDbType.NVarChar).Value = (object)Mail ?? DBNull.Value;
            sqlCom.Parameters.Add("@Observaciones", SqlDbType.NVarChar).Value = (object)Observaciones ?? DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Actualizar
        public void Editar()
        {
            string sqlSentencia = "SP_Proveedor_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Cuit", SqlDbType.NVarChar).Value = (object)Cuit ?? DBNull.Value;
            sqlCom.Parameters.Add("@RazonSocial", SqlDbType.NVarChar).Value = (object)RazonSocial ?? DBNull.Value;
            sqlCom.Parameters.Add("@CondicionIva", SqlDbType.NVarChar).Value = (object)CondicionIva ?? DBNull.Value;
            sqlCom.Parameters.Add("@Calle", SqlDbType.NVarChar).Value = (object)Calle ?? DBNull.Value;
            sqlCom.Parameters.Add("@Numero", SqlDbType.NVarChar).Value = (object)Numero ?? DBNull.Value;
            sqlCom.Parameters.Add("@Barrio", SqlDbType.NVarChar).Value = (object)Barrio ?? DBNull.Value;
            sqlCom.Parameters.Add("@Localidad", SqlDbType.NVarChar).Value = (object)Localidad ?? DBNull.Value;
            sqlCom.Parameters.Add("@Provincia", SqlDbType.NVarChar).Value = (object)Provincia ?? DBNull.Value;
            sqlCom.Parameters.Add("@CodigoPostal", SqlDbType.NVarChar).Value = (object)CodigoPostal ?? DBNull.Value;
            sqlCom.Parameters.Add("@Telefono", SqlDbType.NVarChar).Value = (object)Telefono ?? DBNull.Value;
            sqlCom.Parameters.Add("@Mail", SqlDbType.NVarChar).Value = (object)Mail ?? DBNull.Value;
            sqlCom.Parameters.Add("@Observaciones", SqlDbType.NVarChar).Value = (object)Observaciones ?? DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Eliminar()
        {
            string sqlSentencia = "SP_Proveedor_D";
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
            string sqlSentencia = "SP_Proveedor_Activar";
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
