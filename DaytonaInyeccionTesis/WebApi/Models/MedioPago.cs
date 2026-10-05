using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class MedioPago
    {
        private string connectionstring = Config.Conexion;

        // Medios activos con su comision y cuenta destino
        public DataTable Listar()
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_MedioPago_GetAll", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            return Ejecutar(sqlCnn, sqlCom);
        }

        // Pagos registrados en una venta
        public DataTable PagosDeVenta(int idVenta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_VentaPago_GetByVenta", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdVenta", SqlDbType.Int).Value = idVenta;
            return Ejecutar(sqlCnn, sqlCom);
        }

        // Saldo y movimientos de banco / MP
        public DataTable ResumenCuentas(DateTime? desde, DateTime? hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_CuentaFinanciera_Resumen", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value : DBNull.Value;
            return Ejecutar(sqlCnn, sqlCom);
        }

        // Cuanto se cobro por cada medio en un periodo
        public DataTable PorMedio(DateTime? desde, DateTime? hasta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand("SP_Venta_PorMedioPago", sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value : DBNull.Value;
            sqlCom.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value : DBNull.Value;
            return Ejecutar(sqlCnn, sqlCom);
        }

        private DataTable Ejecutar(SqlConnection cnn, SqlCommand cmd)
        {
            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = cmd;
            DataSet ds = new DataSet();
            cnn.Open();
            da.Fill(ds);
            cnn.Close();
            return ds.Tables[0];
        }
    }
}
