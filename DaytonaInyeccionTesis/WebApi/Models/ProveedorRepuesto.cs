using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class ProveedorRepuesto
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public int IdProveedor { get; set; }

        public string CodigoProveedor { get; set; }
        public string Articulo { get; set; }          // codigo del fabricante
        public string RubroTexto { get; set; }
        public string MarcaTexto { get; set; }
        public string Descripcion { get; set; }

        public decimal PrecioLista { get; set; }
        public decimal DescuentoRubro { get; set; }
        public decimal DescuentoGeneral { get; set; }
        public decimal PrecioCompra { get; set; }     // costo con descuentos aplicados

        public int? IdRubro { get; set; }
        public int? IdRepuesto { get; set; }
        public bool Activo { get; set; }

        /* ----------------------------------------------------------
           Solo los articulos ENLAZADOS a un repuesto del catalogo.
           Es lo que consume la comparacion de precios en Reposicion
           sugerida: no tiene sentido devolver las 53.188 filas de la
           lista, porque el 99% no forma parte del catalogo propio.
           ---------------------------------------------------------- */
        public DataTable ListarEnlazados()
        {
            string sqlSentencia = "SP_ProveedorRepuesto_GetEnlazados";
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

        // Busqueda dentro de la lista de un proveedor, para incorporar
        // articulos al catalogo propio.
        public DataTable Buscar(int idProveedor, string texto, bool soloSinEnlazar, int tope)
        {
            string sqlSentencia = "SP_ProveedorRepuesto_Buscar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdProveedor", SqlDbType.Int).Value =
                idProveedor > 0 ? (object)idProveedor : DBNull.Value;
            sqlCom.Parameters.Add("@Texto", SqlDbType.VarChar, 100).Value =
                string.IsNullOrEmpty(texto) ? (object)DBNull.Value : texto;
            sqlCom.Parameters.Add("@SoloSinEnlazar", SqlDbType.Bit).Value = soloSinEnlazar;
            sqlCom.Parameters.Add("@Tope", SqlDbType.Int).Value = tope > 0 ? tope : 100;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Candidatos a enlazar con el catalogo propio, con nivel de confianza
        public DataTable SugerirEnlaces(int idProveedor)
        {
            string sqlSentencia = "SP_Proveedor_SugerirEnlaces";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Corta el enlace: el articulo vuelve a ser una oferta suelta (script 71)
        public void Desvincular()
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_ProveedorRepuesto_Desvincular", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdListaProveedor", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        // Confirma el enlace entre un articulo de la lista y un repuesto propio
        public void Enlazar()
        {
            string sqlSentencia = "SP_Proveedor_EnlazarRepuesto";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdListaProveedor", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value =
                IdRepuesto.HasValue ? (object)IdRepuesto.Value : DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}
