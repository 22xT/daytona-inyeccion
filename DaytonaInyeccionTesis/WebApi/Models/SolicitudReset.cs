using System;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class SolicitudReset
    {
        // Propiedades
        public int Id { get; set; }
        public string Correo { get; set; }
        public int? IdUsuario { get; set; }
        public string Mensaje { get; set; }
        public string Estado { get; set; }
        public DateTime FechaSolicitud { get; set; }
        public DateTime? FechaProceso { get; set; }
        public int? IdUsuarioProceso { get; set; }

        private string connectionstring = Config.Conexion;

        public int Guardar()
        {
            string sqlSentencia = "SP_SolicitudReset_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Correo", SqlDbType.NVarChar, 150).Value = Correo;
            sqlCom.Parameters.Add("@Mensaje", SqlDbType.NVarChar, 500).Value =
                string.IsNullOrWhiteSpace(Mensaje) ? (object)DBNull.Value : Mensaje;

            sqlCnn.Open();
            int idNuevo = Convert.ToInt32(sqlCom.ExecuteScalar());
            sqlCnn.Close();
            return idNuevo;
        }

        public DataTable ListarPendientes()
        {
            string sqlSentencia = "SP_SolicitudReset_GetPendientes";
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

        public void Procesar(int idUsuarioProceso, string estado)
        {
            string sqlSentencia = "SP_SolicitudReset_Procesar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@IdUsuarioProceso", SqlDbType.Int).Value = idUsuarioProceso;
            sqlCom.Parameters.Add("@Estado", SqlDbType.NVarChar, 20).Value = estado ?? "Procesada";

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_SolicitudReset_GetAll";
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