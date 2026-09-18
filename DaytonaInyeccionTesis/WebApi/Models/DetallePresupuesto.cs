using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class DetallePresupuesto
    {
        private string connectionstring = Config.Conexion;
        public int Id { get; set; }
        public int IdPresupuesto { get; set; }
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public decimal PrecioUnitario { get; set; }

        // El SP recalcula el Total del presupuesto en la misma operacion.
        // Si el repuesto ya estaba cargado, suma la cantidad en vez de duplicar la fila.
        public void Guardar()
        {
            string sqlSentencia = "SP_DetallePresupuesto_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@IdPresupuesto", SqlDbType.Int).Value = IdPresupuesto;
            sqlCom.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = IdRepuesto;
            sqlCom.Parameters.Add("@Cantidad", SqlDbType.Int).Value = Cantidad;
            sqlCom.Parameters.Add("@PrecioUnitario", SqlDbType.Decimal).Value = PrecioUnitario;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}
