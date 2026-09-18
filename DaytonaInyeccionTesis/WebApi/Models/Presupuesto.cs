using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Presupuesto
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public int Numero { get; set; }
        public DateTime Fecha { get; set; }
        public DateTime FechaVencimiento { get; set; }

        // Puede ser null: se presupuesta sin cliente registrado
        public int? IdCliente { get; set; }
        public string NombreOcasional { get; set; }
        public string TelefonoOcasional { get; set; }
        public string TipoCliente { get; set; }

        public decimal Total { get; set; }
        public int IdUsuario { get; set; }
        public int? IdVenta { get; set; }
        public bool Activo { get; set; }
        public string Observaciones { get; set; }

        // Dias de validez del presupuesto. Si no viene, el SP usa 7.
        public int DiasValidez { get; set; }

        // Listar todos los presupuestos
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Presupuesto_GetAll";
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

        // Devuelve dos tablas: cabecera y detalle
        public DataSet ListarPorId()
        {
            string sqlSentencia = "SP_Presupuesto_GetId";
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

        public DataTable Filtrar(DateTime? desde, DateTime? hasta, int idCliente, string estado, string texto)
        {
            string sqlSentencia = "SP_Presupuesto_Filtrar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@FechaDesde", SqlDbType.DateTime).Value =
                desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@FechaHasta", SqlDbType.DateTime).Value =
                hasta.HasValue ? (object)hasta.Value : DBNull.Value;
            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value =
                idCliente > 0 ? (object)idCliente : DBNull.Value;
            sqlCom.Parameters.Add("@Estado", SqlDbType.NVarChar, 20).Value =
                string.IsNullOrEmpty(estado) ? (object)DBNull.Value : estado;
            sqlCom.Parameters.Add("@Texto", SqlDbType.NVarChar, 100).Value =
                string.IsNullOrEmpty(texto) ? (object)DBNull.Value : texto;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // El SP devuelve Id y Numero. Se usa reader en vez de ExecuteScalar
        // para poder leer los dos: el Numero es el que ve el cliente en el papel.
        public int Guardar()
        {
            string sqlSentencia = "SP_Presupuesto_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value =
                IdCliente.HasValue && IdCliente.Value > 0 ? (object)IdCliente.Value : DBNull.Value;
            sqlCom.Parameters.Add("@NombreOcasional", SqlDbType.NVarChar, 80).Value =
                string.IsNullOrEmpty(NombreOcasional) ? (object)DBNull.Value : NombreOcasional;
            sqlCom.Parameters.Add("@TelefonoOcasional", SqlDbType.NVarChar, 30).Value =
                string.IsNullOrEmpty(TelefonoOcasional) ? (object)DBNull.Value : TelefonoOcasional;
            sqlCom.Parameters.Add("@TipoCliente", SqlDbType.NVarChar, 20).Value =
                string.IsNullOrEmpty(TipoCliente) ? "Publico" : TipoCliente;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;
            sqlCom.Parameters.Add("@DiasValidez", SqlDbType.Int).Value =
                DiasValidez > 0 ? DiasValidez : 7;
            sqlCom.Parameters.Add("@Observaciones", SqlDbType.NVarChar, 300).Value =
                string.IsNullOrEmpty(Observaciones) ? (object)DBNull.Value : Observaciones;

            sqlCnn.Open();
            SqlDataReader dr = sqlCom.ExecuteReader();
            if (dr.Read())
            {
                Id = Convert.ToInt32(dr["Id"]);
                Numero = Convert.ToInt32(dr["Numero"]);
            }
            dr.Close();
            sqlCnn.Close();

            return Id;
        }

        // Baja logica. El SP no deja anular si ya se convirtio en venta.
        public void Anular()
        {
            string sqlSentencia = "SP_Presupuesto_Anular";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Enlaza el presupuesto con la venta que lo concreto
        public void VincularVenta(int idVenta)
        {
            string sqlSentencia = "SP_Presupuesto_VincularVenta";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdPresupuesto", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@IdVenta", SqlDbType.Int).Value = idVenta;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}
