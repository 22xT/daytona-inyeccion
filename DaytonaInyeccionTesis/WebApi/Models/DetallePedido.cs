using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class DetallePedido
    {
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public int IdPedido { get; set; }
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public decimal PrecioUnitario { get; set; }

        public DataTable ListarPorPedido()
        {
            string sqlSentencia = @"
                SELECT dp.Id, r.Descripcion AS Repuesto, dp.Cantidad, dp.PrecioUnitario, dp.Subtotal
                FROM DetallePedido dp
                INNER JOIN Repuesto r ON dp.IdRepuesto = r.Id
                WHERE dp.IdPedido = @IdPedido";

            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.Text;
            sqlCom.Parameters.Add("@IdPedido", SqlDbType.Int).Value = IdPedido;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        public void Guardar()
        {
            string sqlSentencia = "SP_DetallePedido_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdPedido", SqlDbType.Int).Value = IdPedido;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = IdRepuesto;
            sqlCom.Parameters.Add("@Cantidad", SqlDbType.Int).Value = Cantidad;
            sqlCom.Parameters.Add("@PrecioUnitario", SqlDbType.Decimal).Value = PrecioUnitario;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Eliminar()
        {
            string sqlSentencia = "SP_DetallePedido_D";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}