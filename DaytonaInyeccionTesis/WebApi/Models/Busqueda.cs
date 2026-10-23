using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Busqueda
    {
        // La cadena vive en Web.config, no en el codigo.
        // En Azure se reemplaza desde la configuracion del App Service.
        private string connectionstring = Config.Conexion;

        /* ----------------------------------------------------------
           Devuelve DOS tablas:
             [0] lo que hay en el catalogo propio, con stock
             [1] lo que ofrecen los proveedores

           Van separadas a proposito: "lo tengo" y "lo podria
           conseguir" son respuestas de naturaleza distinta y no
           deberian competir en una misma lista ordenada.
           ---------------------------------------------------------- */
        public DataSet Universal(string texto, int idProveedor, bool soloConStock, int tope)
        {
            string sqlSentencia = "SP_Busqueda_Universal";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Texto", SqlDbType.VarChar, 200).Value = (object)texto ?? DBNull.Value;
            sqlCom.Parameters.Add("@IdProveedor", SqlDbType.Int).Value =
                idProveedor > 0 ? (object)idProveedor : DBNull.Value;
            sqlCom.Parameters.Add("@SoloConStock", SqlDbType.Bit).Value = soloConStock;
            sqlCom.Parameters.Add("@Tope", SqlDbType.Int).Value = tope > 0 ? tope : 60;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds;
        }

        /* ----------------------------------------------------------
           Registro de busquedas (script 78). Anota que se busco y
           que encontro: con stock, sin stock, en proveedores o nada.
           Se guardan los ids que se mostraron para saber despues si
           la busqueda termino en venta.
           ---------------------------------------------------------- */
        public void Registrar(int idUsuario, string texto, string origen, DataSet resultado)
        {
            int local = 0, conStock = 0, proveedor = 0;
            System.Text.StringBuilder ids = new System.Text.StringBuilder(" ");

            if (resultado != null && resultado.Tables.Count > 0)
            {
                DataTable t = resultado.Tables[0];
                foreach (DataRow r in t.Rows)
                {
                    // Las fichas armadas al vincular no cuentan como del local
                    if (t.Columns.Contains("EnLocal") && r["EnLocal"] != DBNull.Value && Convert.ToInt32(r["EnLocal"]) == 0)
                        continue;
                    local++;
                    if (t.Columns.Contains("Stock") && r["Stock"] != DBNull.Value && Convert.ToDecimal(r["Stock"]) > 0) conStock++;
                    if (t.Columns.Contains("Id") && r["Id"] != DBNull.Value && ids.Length < 780)
                        ids.Append(Convert.ToString(r["Id"])).Append(' ');
                }
            }
            if (resultado != null && resultado.Tables.Count > 1) proveedor = resultado.Tables[1].Rows.Count;

            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Busqueda_Registrar", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 10;
                cmd.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario > 0 ? (object)idUsuario : DBNull.Value;
                cmd.Parameters.Add("@Texto", SqlDbType.VarChar, 200).Value =
                    texto != null && texto.Length > 200 ? texto.Substring(0, 200) : (object)texto ?? DBNull.Value;
                cmd.Parameters.Add("@Origen", SqlDbType.VarChar, 20).Value = string.IsNullOrEmpty(origen) ? "BUSCADOR" : origen;
                cmd.Parameters.Add("@ResultadosLocal", SqlDbType.Int).Value = local;
                cmd.Parameters.Add("@ConStock", SqlDbType.Int).Value = conStock;
                cmd.Parameters.Add("@ResultadosProveedor", SqlDbType.Int).Value = proveedor;
                cmd.Parameters.Add("@IdsMostrados", SqlDbType.VarChar, 800).Value = ids.Length > 1 ? (object)ids.ToString() : DBNull.Value;
                cnn.Open();
                cmd.ExecuteNonQuery();
            }
        }

        public DataSet Reporte(int dias)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Busqueda_Reporte", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.CommandTimeout = 120;
                cmd.Parameters.Add("@Dias", SqlDbType.Int).Value = dias > 0 ? dias : 30;
                DataSet ds = new DataSet();
                new SqlDataAdapter(cmd).Fill(ds);
                return ds;
            }
        }

        // Repuestos que estan mas baratos en otro proveedor
        public DataTable Oportunidades(decimal diferenciaMinima)
        {
            string sqlSentencia = "SP_Ahorro_Oportunidades";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@DiferenciaMinima", SqlDbType.Decimal).Value = diferenciaMinima;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Que porcentaje de lo que se vende esta vinculado a algun proveedor
        public DataTable Cobertura(int dias)
        {
            string sqlSentencia = "SP_Centralizador_Cobertura";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Dias", SqlDbType.Int).Value = dias > 0 ? dias : 120;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }
    }
}
