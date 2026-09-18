using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Cliente
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public string Dni { get; set; }
        public string Nombre { get; set; }
        public string Apellido { get; set; }
        public string Telefono { get; set; }
        public string Mail { get; set; }
        public string Calle { get; set; }
        public string Numero { get; set; }
        public bool Activo { get; set; }

        // Marca de mecanico: habilita cuenta corriente y 10% de descuento fijo
        public bool EsMecanico { get; set; }

        // Listar todos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Cliente_GetAll";
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
            string sqlSentencia = "SP_Cliente_GetById";
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

        // Insertar. Devuelve el Id generado, para poder dejar seleccionado
        // al cliente recien creado sin volver a buscarlo en la lista.
        public int Guardar()
        {
            string sqlSentencia = "SP_Cliente_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            // null se convierte a DBNull para que el campo opcional quede NULL en la base
            sqlCom.Parameters.Add("@Dni", SqlDbType.NVarChar).Value = (object)Dni ?? DBNull.Value;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Apellido", SqlDbType.NVarChar).Value = (object)Apellido ?? DBNull.Value;
            sqlCom.Parameters.Add("@Telefono", SqlDbType.NVarChar).Value = (object)Telefono ?? DBNull.Value;
            sqlCom.Parameters.Add("@Mail", SqlDbType.NVarChar).Value = (object)Mail ?? DBNull.Value;
            sqlCom.Parameters.Add("@Calle", SqlDbType.NVarChar).Value = (object)Calle ?? DBNull.Value;
            sqlCom.Parameters.Add("@Numero", SqlDbType.NVarChar).Value = (object)Numero ?? DBNull.Value;
            sqlCom.Parameters.Add("@EsMecanico", SqlDbType.Bit).Value = EsMecanico;

            sqlCnn.Open();
            object resultado = sqlCom.ExecuteScalar();
            sqlCnn.Close();

            Id = resultado == null || resultado == DBNull.Value ? 0 : Convert.ToInt32(resultado);
            return Id;
        }

        // Actualizar
        public void Editar()
        {
            string sqlSentencia = "SP_Cliente_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@Dni", SqlDbType.NVarChar).Value = (object)Dni ?? DBNull.Value;
            sqlCom.Parameters.Add("@Nombre", SqlDbType.NVarChar).Value = (object)Nombre ?? DBNull.Value;
            sqlCom.Parameters.Add("@Apellido", SqlDbType.NVarChar).Value = (object)Apellido ?? DBNull.Value;
            sqlCom.Parameters.Add("@Telefono", SqlDbType.NVarChar).Value = (object)Telefono ?? DBNull.Value;
            sqlCom.Parameters.Add("@Mail", SqlDbType.NVarChar).Value = (object)Mail ?? DBNull.Value;
            sqlCom.Parameters.Add("@Calle", SqlDbType.NVarChar).Value = (object)Calle ?? DBNull.Value;
            sqlCom.Parameters.Add("@Numero", SqlDbType.NVarChar).Value = (object)Numero ?? DBNull.Value;
            sqlCom.Parameters.Add("@EsMecanico", SqlDbType.Bit).Value = EsMecanico;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Baja logica: marca el cliente como inactivo (no borra)
        public void Eliminar()
        {
            string sqlSentencia = "SP_Cliente_D";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Reactiva un cliente dado de baja
        public void Activar()
        {
            string sqlSentencia = "SP_Cliente_Activar";
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