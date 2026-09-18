using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class CuentaCorriente
    {
        // La cadena vive en Web.config, no en el codigo.
        // En Azure se reemplaza desde la configuracion del App Service.
        private string connectionstring = Config.Conexion;

        public int IdCliente { get; set; }
        public decimal Monto { get; set; }
        public string Concepto { get; set; }
        public string Observaciones { get; set; }

        // Se completan desde el token en el controller, nunca desde el body
        public int IdUsuario { get; set; }

        /* ----------------------------------------------------------
           Listado de clientes con cuenta corriente.
           El saldo NO sale de un campo: se deriva sumando los
           movimientos dentro del procedimiento.
           ---------------------------------------------------------- */
        public DataTable ListarTodos(bool soloConSaldo, string texto)
        {
            string sqlSentencia = "SP_CuentaCorriente_GetAll";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@SoloConSaldo", SqlDbType.Bit).Value = soloConSaldo;
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

        // Saldo y resumen de un cliente
        public DataTable ObtenerSaldo()
        {
            string sqlSentencia = "SP_CuentaCorriente_GetSaldo";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value = IdCliente;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Libro de movimientos con el saldo acumulado calculado al vuelo
        public DataTable ListarMovimientos(DateTime? desde, DateTime? hasta)
        {
            string sqlSentencia = "SP_CuentaCorriente_GetMovimientos";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value = IdCliente;
            sqlCom.Parameters.Add("@FechaDesde", SqlDbType.DateTime).Value =
                desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@FechaHasta", SqlDbType.DateTime).Value =
                hasta.HasValue ? (object)hasta.Value : DBNull.Value;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        /* ----------------------------------------------------------
           Registrar un cobro. El SP hace dos cosas en la misma
           transaccion: reduce el saldo y registra el ingreso en caja.
           Devuelve el saldo actualizado.
           ---------------------------------------------------------- */
        public DataTable RegistrarPago()
        {
            string sqlSentencia = "SP_CuentaCorriente_RegistrarPago";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value = IdCliente;
            sqlCom.Parameters.Add("@Monto", SqlDbType.Decimal).Value = Monto;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;
            sqlCom.Parameters.Add("@Observaciones", SqlDbType.VarChar, 300).Value =
                string.IsNullOrEmpty(Observaciones) ? (object)DBNull.Value : Observaciones;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables.Count > 0 ? ds.Tables[0] : null;
        }

        // Ajuste manual. No toca la caja: corrige el registro, no mueve dinero.
        public void RegistrarAjuste()
        {
            string sqlSentencia = "SP_CuentaCorriente_Ajuste";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value = IdCliente;
            sqlCom.Parameters.Add("@Monto", SqlDbType.Decimal).Value = Monto;
            sqlCom.Parameters.Add("@Concepto", SqlDbType.VarChar, 120).Value =
                (object)Concepto ?? DBNull.Value;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;
            sqlCom.Parameters.Add("@Observaciones", SqlDbType.VarChar, 300).Value =
                string.IsNullOrEmpty(Observaciones) ? (object)DBNull.Value : Observaciones;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}
