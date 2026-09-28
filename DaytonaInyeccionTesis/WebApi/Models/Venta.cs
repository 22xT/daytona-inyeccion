using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    public class Venta
    {
        // La cadena vive en Web.config, no en el codigo.
        // En Azure se reemplaza desde la configuracion del App Service.
        private string connectionstring = Config.Conexion;

        public int Id { get; set; }
        public DateTime Fecha { get; set; }
        public int IdCliente { get; set; }
        public int IdUsuario { get; set; }
        public int IdEstadoVenta { get; set; }
        public decimal Total { get; set; }

        /* ---------- Descuento y forma de pago ---------- */

        // Se guardan el porcentaje Y el importe: reimprimir un
        // comprobante viejo tiene que dar exactamente lo mismo.
        public decimal PorcentajeDescuento { get; set; }
        public decimal Descuento { get; set; }

        public decimal Neto { get; set; }
        public decimal Iva { get; set; }

        // 'Contado' | 'CuentaCorriente'
        public string FormaPago { get; set; }

        // Parte que el cliente paga en el momento. En una venta de
        // contado es el total; en una fiada puede ser cero o una
        // entrega parcial. Solo esto entra a la caja.
        public decimal? Entrega { get; set; }

        /* ---------- Datos de mostrador ---------- */

        public string NombreOcasional { get; set; }
        public string TelefonoOcasional { get; set; }
        public string TipoCliente { get; set; }

        // Lista de items que llega del front al guardar
        public List<DetalleVenta> Detalle { get; set; }

        // Lo devuelve el SP: total menos entrega. Es lo que quedo debiendo.
        public decimal SaldoGenerado { get; set; }

        // Token unico de la operacion, generado por el cliente. Evita que
        // un doble clic o un reenvio creen dos ventas iguales.
        public Guid? TokenOperacion { get; set; }

        // Listar todas
        public DataTable ListarTodos()
        {
            string sqlSentencia = "SP_Venta_GetAll";
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

        // Listar una por Id (cabecera)
        public DataTable ListarPorId()
        {
            string sqlSentencia = "SP_Venta_GetId";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;

            SqlDataAdapter da = new SqlDataAdapter();
            da.SelectCommand = sqlCom;

            DataSet ds = new DataSet();
            sqlCnn.Open();
            da.Fill(ds);
            sqlCnn.Close();

            return ds.Tables[0];
        }

        // Listar anuladas en las ultimas 24hs (para popup admin)
        public DataTable ListarAnuladasRecientes()
        {
            string sqlSentencia = "SP_Venta_GetAnuladasRecientes";
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

        // Guardar venta con su detalle (transaccion en SP, usa TVP)
        public int Guardar()
        {
            string sqlSentencia = "SP_Venta_I";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;

            sqlCom.Parameters.Add("@IdCliente", SqlDbType.Int).Value = IdCliente;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;

            sqlCom.Parameters.Add("@PorcentajeDescuento", SqlDbType.Decimal).Value = PorcentajeDescuento;
            sqlCom.Parameters.Add("@FormaPago", SqlDbType.VarChar, 20).Value =
                string.IsNullOrEmpty(FormaPago) ? "Contado" : FormaPago;
            // NULL deja que el SP decida: total si es contado, cero si es a credito
            sqlCom.Parameters.Add("@Entrega", SqlDbType.Decimal).Value =
                Entrega.HasValue ? (object)Entrega.Value : DBNull.Value;
            sqlCom.Parameters.Add("@NombreOcasional", SqlDbType.NVarChar, 80).Value =
                string.IsNullOrEmpty(NombreOcasional) ? (object)DBNull.Value : NombreOcasional;
            sqlCom.Parameters.Add("@TelefonoOcasional", SqlDbType.NVarChar, 30).Value =
                string.IsNullOrEmpty(TelefonoOcasional) ? (object)DBNull.Value : TelefonoOcasional;
            sqlCom.Parameters.Add("@TipoCliente", SqlDbType.NVarChar, 20).Value =
                string.IsNullOrEmpty(TipoCliente) ? (object)DBNull.Value : TipoCliente;

            // Armar el TVP con el detalle
            DataTable tablaDetalle = new DataTable();
            tablaDetalle.Columns.Add("IdRepuesto", typeof(int));
            tablaDetalle.Columns.Add("Cantidad", typeof(int));
            tablaDetalle.Columns.Add("PrecioUnitario", typeof(decimal));

            if (Detalle != null)
            {
                foreach (DetalleVenta d in Detalle)
                {
                    tablaDetalle.Rows.Add(d.IdRepuesto, d.Cantidad, d.PrecioUnitario);
                }
            }

            SqlParameter pDetalle = sqlCom.Parameters.AddWithValue("@Detalle", tablaDetalle);
            pDetalle.SqlDbType = SqlDbType.Structured;
            pDetalle.TypeName = "dbo.DetalleVentaType";

            // El SP devuelve IdVenta, Total, Descuento, Entrega y SaldoGenerado.
            // Se leen todos: el saldo generado es lo que hay que informarle
            // al vendedor cuando la venta fue a cuenta corriente.
            sqlCnn.Open();
            SqlDataReader dr = sqlCom.ExecuteReader();
            if (dr.Read())
            {
                Id        = Convert.ToInt32(dr["IdVenta"]);
                Total     = Convert.ToDecimal(dr["Total"]);
                Descuento = Convert.ToDecimal(dr["Descuento"]);
                Entrega   = Convert.ToDecimal(dr["Entrega"]);
                SaldoGenerado = Convert.ToDecimal(dr["SaldoGenerado"]);
            }
            dr.Close();
            sqlCnn.Close();

            return Id;
        }

        /* ---------- Idempotencia ---------- */

        // Reserva el token. Devuelve NUEVA, EXISTE (con IdVenta) o EN_CURSO.
        public string ReservarOperacion(out int idVentaExistente)
        {
            idVentaExistente = 0;
            string sqlSentencia = "SP_VentaOperacion_Reservar";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Token", SqlDbType.UniqueIdentifier).Value = TokenOperacion.Value;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = IdUsuario;

            string estado = "NUEVA";
            sqlCnn.Open();
            SqlDataReader dr = sqlCom.ExecuteReader();
            if (dr.Read())
            {
                estado = Convert.ToString(dr["Estado"]);
                if (dr["IdVenta"] != DBNull.Value) idVentaExistente = Convert.ToInt32(dr["IdVenta"]);
            }
            dr.Close();
            sqlCnn.Close();
            return estado;
        }

        public void CompletarOperacion()
        {
            EjecutarSimple("SP_VentaOperacion_Completar", true);
        }

        public void LiberarOperacion()
        {
            EjecutarSimple("SP_VentaOperacion_Liberar", false);
        }

        private void EjecutarSimple(string sp, bool conIdVenta)
        {
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sp, sqlCnn);
            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Token", SqlDbType.UniqueIdentifier).Value = TokenOperacion.Value;
            if (conIdVenta) sqlCom.Parameters.Add("@IdVenta", SqlDbType.Int).Value = Id;
            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }

        public void Anular(int idUsuario)
        {
            string sqlSentencia = "SP_Venta_Anular";
            SqlConnection sqlCnn = new SqlConnection(connectionstring);
            SqlCommand sqlCom = new SqlCommand(sqlSentencia, sqlCnn);

            sqlCom.CommandType = CommandType.StoredProcedure;
            sqlCom.Parameters.Add("@Id", SqlDbType.Int).Value = Id;
            sqlCom.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;

            sqlCnn.Open();
            sqlCom.ExecuteNonQuery();
            sqlCnn.Close();
        }
    }
}
