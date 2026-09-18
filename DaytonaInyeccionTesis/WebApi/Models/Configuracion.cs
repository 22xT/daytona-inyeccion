using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Configuracion
    {
        private string connectionstring = Config.Conexion;

        // Parametro
        public string Clave { get; set; }
        public string Valor { get; set; }

        // Margen por rubro
        public int IdRubro { get; set; }
        public decimal? Margen { get; set; }

        /* ---------- Parametros ---------- */

        public DataTable ListarParametros()
        {
            string sqlSentencia = "SP_Parametro_GetAll";
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

        public void GuardarParametro()
        {
            string sqlSentencia = "SP_Parametro_U";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Clave", SqlDbType.VarChar, 50).Value = Clave;
            sqlCom.Parameters.Add("@Valor", SqlDbType.VarChar, 200).Value = (object)Valor ?? DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        /* ---------- Margenes por rubro ---------- */

        public DataTable ListarMargenes(bool soloConMargen, string texto)
        {
            string sqlSentencia = "SP_Rubro_GetMargenes";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@SoloConMargen", SqlDbType.Bit).Value = soloConMargen;
            sqlCom.Parameters.Add("@Texto", SqlDbType.VarChar, 100).Value =
                string.IsNullOrEmpty(texto) ? (object)DBNull.Value : texto;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Margen null borra la excepcion: el rubro vuelve al margen general
        public void GuardarMargen()
        {
            string sqlSentencia = "SP_Rubro_SetMargen";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdRubro", SqlDbType.Int).Value = IdRubro;
            sqlCom.Parameters.Add("@Margen", SqlDbType.Decimal).Value =
                Margen.HasValue ? (object)Margen.Value : DBNull.Value;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}
