using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Recepcion de mercaderia, cuenta corriente y pagos a proveedores.
       La recepcion genera deuda; el dinero sale con el pago. */

    public class RecepcionLinea
    {
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public decimal CostoUnitario { get; set; }
    }

    public class Recepcion
    {
        public List<RecepcionLinea> Lineas { get; set; }
        public string TipoComprobante { get; set; }
        public string NumeroComprobante { get; set; }
        public DateTime FechaComprobante { get; set; }
        public decimal TotalComprobante { get; set; }
        public int? IdAdjunto { get; set; }
        public string Observacion { get; set; }
    }

    public class PagoProveedorDto
    {
        public int IdProveedor { get; set; }
        public int IdCuentaFinanciera { get; set; }
        public decimal Importe { get; set; }
        public string Referencia { get; set; }
    }

    public class Compras
    {
        private string connectionstring = Config.Conexion;
        private static object N(object v) { return v ?? DBNull.Value; }

        public DataSet ParaRecepcion(int idPedido)
        {
            return ConsultarDs("SP_Pedido_ParaRecepcion", c => c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido);
        }

        public DataTable ResumenRecepcion()
        {
            return ConsultarDs("SP_Pedido_ResumenRecepcion", c => { }).Tables[0];
        }

        public DataTable Recibir(int idPedido, Recepcion r, int idUsuario)
        {
            DataTable lineas = new DataTable();
            lineas.Columns.Add("IdRepuesto", typeof(int));
            lineas.Columns.Add("Cantidad", typeof(int));
            lineas.Columns.Add("CostoUnitario", typeof(decimal));
            foreach (RecepcionLinea l in r.Lineas) lineas.Rows.Add(l.IdRepuesto, l.Cantidad, l.CostoUnitario);

            return ConsultarDs("SP_Pedido_Recibir", c =>
            {
                c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido;
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", lineas);
                p.SqlDbType = SqlDbType.Structured;
                p.TypeName = "dbo.RecepcionLineaType";
                c.Parameters.Add("@TipoComprobante", SqlDbType.VarChar, 20).Value = N(r.TipoComprobante);
                c.Parameters.Add("@NumeroComprobante", SqlDbType.VarChar, 40).Value = N(r.NumeroComprobante);
                c.Parameters.Add("@FechaComprobante", SqlDbType.Date).Value = r.FechaComprobante;
                c.Parameters.Add("@TotalComprobante", SqlDbType.Decimal).Value = r.TotalComprobante;
                c.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = N(r.IdAdjunto);
                c.Parameters.Add("@Observacion", SqlDbType.NVarChar, 250).Value = N(r.Observacion);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        public void AnularRecepcion(int idRecepcion, string motivo, int idUsuario)
        {
            Ejecutar("SP_RecepcionPedido_Anular", c =>
            {
                c.Parameters.Add("@IdRecepcion", SqlDbType.Int).Value = idRecepcion;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public void CerrarFaltantes(int idPedido, string motivo, int idUsuario)
        {
            Ejecutar("SP_Pedido_CerrarFaltantes", c =>
            {
                c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public DataTable SaldosProveedores()
        {
            return ConsultarDs("SP_CtaCteProveedor_Saldos", c => { }).Tables[0];
        }

        public DataTable MovimientosProveedor(int idProveedor)
        {
            return ConsultarDs("SP_CtaCteProveedor_Movimientos", c => c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor).Tables[0];
        }

        public void AjusteProveedor(int idProveedor, decimal monto, string motivo, int idUsuario)
        {
            Ejecutar("SP_CtaCteProveedor_Ajuste", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor;
                c.Parameters.Add("@Monto", SqlDbType.Decimal).Value = monto;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public DataTable Pagar(PagoProveedorDto p, int idUsuario)
        {
            return ConsultarDs("SP_PagoProveedor_I", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = p.IdProveedor;
                c.Parameters.Add("@IdCuentaFinanciera", SqlDbType.Int).Value = p.IdCuentaFinanciera;
                c.Parameters.Add("@Importe", SqlDbType.Decimal).Value = p.Importe;
                c.Parameters.Add("@Referencia", SqlDbType.NVarChar, 100).Value = N(p.Referencia);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        public void AnularPago(int idPago, string motivo, int idUsuario)
        {
            Ejecutar("SP_PagoProveedor_Anular", c =>
            {
                c.Parameters.Add("@IdPago", SqlDbType.Int).Value = idPago;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        private DataSet ConsultarDs(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                DataSet ds = new DataSet();
                using (SqlDataAdapter da = new SqlDataAdapter(cmd)) { da.Fill(ds); }
                return ds;
            }
        }

        private void Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                cnn.Open();
                cmd.ExecuteNonQuery();
            }
        }
    }
}
