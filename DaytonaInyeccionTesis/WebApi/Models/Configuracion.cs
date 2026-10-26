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
    

        /* ---------- Costos fijos (script 80) ---------- */
        public DataSet ListarCostosFijos()
        {
            return EjecutarCF("SP_CostoFijo_Listar", null);
        }

        public int GuardarCostoFijo(int? id, string concepto, int? idTipoGasto, decimal monto)
        {
            DataSet ds = EjecutarCF("SP_CostoFijo_Guardar", c =>
            {
                c.Parameters.Add("@Id", SqlDbType.Int).Value = id.HasValue && id.Value > 0 ? (object)id.Value : DBNull.Value;
                c.Parameters.Add("@Concepto", SqlDbType.NVarChar, 80).Value = (object)concepto ?? DBNull.Value;
                c.Parameters.Add("@IdTipoGasto", SqlDbType.Int).Value = idTipoGasto.HasValue && idTipoGasto.Value > 0 ? (object)idTipoGasto.Value : DBNull.Value;
                SqlParameter pm = c.Parameters.Add("@MontoMensual", SqlDbType.Decimal);
                pm.Precision = 12; pm.Scale = 2; pm.Value = monto;
            });
            return Convert.ToInt32(ds.Tables[0].Rows[0]["Id"]);
        }

        public void QuitarCostoFijo(int id)
        {
            EjecutarCF("SP_CostoFijo_Quitar", c => c.Parameters.Add("@Id", SqlDbType.Int).Value = id);
        }

        private DataSet EjecutarCF(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                if (parametros != null) parametros(cmd);
                DataSet ds = new DataSet();
                new SqlDataAdapter(cmd).Fill(ds);
                return ds;
            }
        }
    }
}
