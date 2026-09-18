using System;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class DetalleVenta
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public int IdVenta { get; set; }
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public decimal PrecioUnitario { get; set; }
        public decimal Subtotal { get; set; }

        // Listar detalle por venta
        public DataTable ListarPorVenta()
        {
            string sqlSentencia = "SP_DetalleVenta_GetByVenta";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdVenta", SqlDbType.Int).Value = IdVenta;

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
