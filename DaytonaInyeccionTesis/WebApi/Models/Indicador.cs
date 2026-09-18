using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Indicador
    {
        // La cadena vive en Web.config, no en el codigo.
        // En Azure se reemplaza desde la configuracion del App Service.
        private string connectionstring = Config.Conexion;

        // Una sola fila con los contadores del menu:
        // Reposicion, SinStock, PedidosPendientes, ClientesConDeuda, TotalACobrar
        public DataTable Resumen()
        {
            string sqlSentencia = "SP_Indicadores_Menu";
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
    }
}
