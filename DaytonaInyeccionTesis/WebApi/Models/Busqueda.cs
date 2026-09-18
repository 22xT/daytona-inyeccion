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
