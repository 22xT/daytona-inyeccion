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
        // Si los datos vinieron de leer la foto, la lectura queda asociada
        public int? IdLecturaFactura { get; set; }
    }

    // Paso 1: lo que dice la factura
    public class RecepcionFacturaLinea
    {
        public int? IdRepuesto { get; set; }
        public string Codigo { get; set; }
        public string Descripcion { get; set; }
        public int CantidadFacturada { get; set; }
        public decimal CostoUnitario { get; set; }
    }

    public class RecepcionInicio
    {
        public List<RecepcionFacturaLinea> Lineas { get; set; }
        public string TipoComprobante { get; set; }
        public string NumeroComprobante { get; set; }
        public DateTime FechaComprobante { get; set; }
        public decimal TotalComprobante { get; set; }
        public int? IdAdjunto { get; set; }
        public int? IdLecturaFactura { get; set; }
        public string Observacion { get; set; }
    }

    // Paso 3: lo que se conto. IdDetalle null = llego sin estar facturado
    public class RecepcionControlLinea
    {
        public int? IdDetalle { get; set; }
        public int? IdRepuesto { get; set; }
        public int CantidadRecibida { get; set; }
        public int CantidadDanada { get; set; }
        public decimal? CostoUnitario { get; set; }
        public string Observacion { get; set; }
    }

    public class SaldoInicialLinea
    {
        public DateTime Fecha { get; set; }
        public string Comprobante { get; set; }
        public decimal Importe { get; set; }
    }

    public class NotaCreditoDto
    {
        public int IdProveedor { get; set; }
        public string Numero { get; set; }
        public DateTime Fecha { get; set; }
        public decimal Importe { get; set; }
        public int? IdAdjunto { get; set; }
        public List<int> Incidencias { get; set; }
    }

    // Un renglon leido de la factura
    public class FacturaLinea
    {
        public int Orden { get; set; }
        public string Codigo { get; set; }
        public string Descripcion { get; set; }
        public decimal? Cantidad { get; set; }
        public decimal? PrecioUnitario { get; set; }
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

        public void SetStockMinimo(int idRepuesto, int minimo)
        {
            Ejecutar("SP_Stock_SetMinimo", c =>
            {
                c.Parameters.Add("@IdRepuesto", SqlDbType.Int).Value = idRepuesto;
                c.Parameters.Add("@StockMinimo", SqlDbType.Int).Value = minimo;
            });
        }

        public DataSet ReposicionSugerida()
        {
            return ConsultarDs("SP_Reposicion_Sugerida", c => { });
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

        /* ---------- Recepcion en dos tiempos ---------- */

        public int IniciarRecepcion(int idPedido, RecepcionInicio r, int idUsuario)
        {
            DataTable t = new DataTable();
            t.Columns.Add("IdRepuesto", typeof(int));
            t.Columns.Add("Codigo", typeof(string));
            t.Columns.Add("Descripcion", typeof(string));
            t.Columns.Add("CantidadFacturada", typeof(int));
            t.Columns.Add("CostoUnitario", typeof(decimal));
            foreach (RecepcionFacturaLinea l in r.Lineas)
                t.Rows.Add((object)l.IdRepuesto ?? DBNull.Value, (object)Recortar(l.Codigo, 60) ?? DBNull.Value,
                           (object)Recortar(l.Descripcion, 250) ?? DBNull.Value, l.CantidadFacturada, l.CostoUnitario);

            return Convert.ToInt32(ConsultarDs("SP_Recepcion_Iniciar", c =>
            {
                c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido;
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", t);
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.RecepcionFacturaType";
                c.Parameters.Add("@TipoComprobante", SqlDbType.VarChar, 20).Value = N(r.TipoComprobante);
                c.Parameters.Add("@NumeroComprobante", SqlDbType.VarChar, 40).Value = N(r.NumeroComprobante);
                c.Parameters.Add("@FechaComprobante", SqlDbType.Date).Value = r.FechaComprobante;
                c.Parameters.Add("@TotalComprobante", SqlDbType.Decimal).Value = r.TotalComprobante;
                c.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = N(r.IdAdjunto);
                c.Parameters.Add("@IdLecturaFactura", SqlDbType.Int).Value = N(r.IdLecturaFactura);
                c.Parameters.Add("@Observacion", SqlDbType.NVarChar, 250).Value = N(r.Observacion);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0].Rows[0]["IdRecepcion"]);
        }

        public DataTable ConfirmarRecepcion(int idRecepcion, List<RecepcionControlLinea> lineas, int idUsuario)
        {
            DataTable t = new DataTable();
            t.Columns.Add("IdDetalle", typeof(int));
            t.Columns.Add("IdRepuesto", typeof(int));
            t.Columns.Add("CantidadRecibida", typeof(int));
            t.Columns.Add("CantidadDanada", typeof(int));
            t.Columns.Add("CostoUnitario", typeof(decimal));
            t.Columns.Add("Observacion", typeof(string));
            foreach (RecepcionControlLinea l in lineas)
                t.Rows.Add((object)l.IdDetalle ?? DBNull.Value, (object)l.IdRepuesto ?? DBNull.Value,
                           l.CantidadRecibida, l.CantidadDanada, (object)l.CostoUnitario ?? DBNull.Value,
                           (object)Recortar(l.Observacion, 200) ?? DBNull.Value);

            return ConsultarDs("SP_Recepcion_Confirmar", c =>
            {
                c.Parameters.Add("@IdRecepcion", SqlDbType.Int).Value = idRecepcion;
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", t);
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.RecepcionControlType";
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        public DataTable IncidenciasAbiertas(int? idProveedor)
        {
            return ConsultarDs("SP_Incidencia_Abiertas", c =>
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = N(idProveedor)).Tables[0];
        }

        /* ---------- Reclamos, notas de credito y vencimientos ---------- */

        private static DataTable ListaIds(IEnumerable<int> ids)
        {
            DataTable t = new DataTable();
            t.Columns.Add("Id", typeof(int));
            if (ids != null) foreach (int id in new HashSet<int>(ids)) t.Rows.Add(id);
            return t;
        }

        public DataTable Facturas(int? idProveedor)
        {
            return ConsultarDs("SP_CtaCteProveedor_Facturas", c =>
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = N(idProveedor)).Tables[0];
        }

        public DataTable SaldoInicial(int idProveedor, List<SaldoInicialLinea> lineas, int idUsuario)
        {
            DataTable t = new DataTable();
            t.Columns.Add("Fecha", typeof(DateTime));
            t.Columns.Add("Comprobante", typeof(string));
            t.Columns.Add("Importe", typeof(decimal));
            foreach (SaldoInicialLinea l in lineas) t.Rows.Add(l.Fecha.Date, Recortar(l.Comprobante, 80) ?? "", l.Importe);
            return ConsultarDs("SP_CtaCteProveedor_SaldoInicial", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor;
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", t);
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.SaldoInicialType";
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        // Reemplaza o quita la foto de una factura. La anterior queda guardada.
        public void CambiarAdjunto(int idRecepcion, int? idAdjunto, int idUsuario)
        {
            Ejecutar("SP_Recepcion_CambiarAdjunto", c =>
            {
                c.Parameters.Add("@IdRecepcion", SqlDbType.Int).Value = idRecepcion;
                c.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = N(idAdjunto);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public void SetDiasPago(int idProveedor, int dias)
        {
            Ejecutar("SP_Proveedor_SetDiasPago", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor;
                c.Parameters.Add("@DiasPago", SqlDbType.Int).Value = dias;
            });
        }

        public void Reclamar(List<int> ids, string numeroConstancia, int idUsuario)
        {
            Ejecutar("SP_Incidencia_Reclamar", c =>
            {
                SqlParameter p = c.Parameters.AddWithValue("@Ids", ListaIds(ids));
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.IdListType";
                c.Parameters.Add("@NumeroConstancia", SqlDbType.NVarChar, 40).Value = N(numeroConstancia);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public int NotaCredito(NotaCreditoDto n, int idUsuario)
        {
            return Convert.ToInt32(ConsultarDs("SP_NotaCreditoProveedor_I", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = n.IdProveedor;
                c.Parameters.Add("@Numero", SqlDbType.VarChar, 40).Value = N(n.Numero);
                c.Parameters.Add("@Fecha", SqlDbType.Date).Value = n.Fecha;
                c.Parameters.Add("@Importe", SqlDbType.Decimal).Value = n.Importe;
                c.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = N(n.IdAdjunto);
                SqlParameter p = c.Parameters.AddWithValue("@Incidencias", ListaIds(n.Incidencias));
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.IdListType";
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0].Rows[0]["IdNotaCredito"]);
        }

        public void ResolverIncidencia(int id, string accion, string numero, decimal? importe, string motivo, int idUsuario)
        {
            Ejecutar("SP_Incidencia_Resolver", c =>
            {
                c.Parameters.Add("@IdIncidencia", SqlDbType.Int).Value = id;
                c.Parameters.Add("@Accion", SqlDbType.VarChar, 15).Value = N(accion);
                c.Parameters.Add("@Numero", SqlDbType.VarChar, 40).Value = N(numero);
                c.Parameters.Add("@Importe", SqlDbType.Decimal).Value = N(importe);
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        /* ---------- Lectura de factura ---------- */

        public DataTable CruzarFactura(int idPedido, List<FacturaLinea> lineas)
        {
            DataTable t = new DataTable();
            t.Columns.Add("Orden", typeof(int));
            t.Columns.Add("Codigo", typeof(string));
            t.Columns.Add("Descripcion", typeof(string));
            t.Columns.Add("Cantidad", typeof(decimal));
            t.Columns.Add("PrecioUnitario", typeof(decimal));
            foreach (FacturaLinea l in lineas)
                t.Rows.Add(l.Orden,
                           (object)Recortar(l.Codigo, 60) ?? DBNull.Value,
                           (object)Recortar(l.Descripcion, 250) ?? DBNull.Value,
                           (object)l.Cantidad ?? DBNull.Value,
                           (object)l.PrecioUnitario ?? DBNull.Value);

            return ConsultarDs("SP_Factura_Cruzar", c =>
            {
                c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido;
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", t);
                p.SqlDbType = SqlDbType.Structured;
                p.TypeName = "dbo.FacturaLineaType";
            }).Tables[0];
        }

        public int RegistrarLectura(int idAdjunto, int idPedido, string modelo, bool exito, string respuesta,
                                    string error, int duracionMs, int? renglones, int? identificados, int idUsuario)
        {
            return Convert.ToInt32(ConsultarDs("SP_LecturaFactura_I", c =>
            {
                c.Parameters.Add("@IdAdjunto", SqlDbType.Int).Value = idAdjunto;
                c.Parameters.Add("@IdPedido", SqlDbType.Int).Value = idPedido;
                c.Parameters.Add("@Modelo", SqlDbType.VarChar, 60).Value = modelo;
                c.Parameters.Add("@Exito", SqlDbType.Bit).Value = exito;
                c.Parameters.Add("@Respuesta", SqlDbType.NVarChar, -1).Value = N(respuesta);
                c.Parameters.Add("@Error", SqlDbType.NVarChar, 500).Value = N(Recortar(error, 500));
                c.Parameters.Add("@DuracionMs", SqlDbType.Int).Value = duracionMs;
                c.Parameters.Add("@Renglones", SqlDbType.Int).Value = N(renglones);
                c.Parameters.Add("@Identificados", SqlDbType.Int).Value = N(identificados);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0].Rows[0]["IdLectura"]);
        }

        public void VincularLectura(int idLectura, int idRecepcion)
        {
            Ejecutar("SP_LecturaFactura_Vincular", c =>
            {
                c.Parameters.Add("@IdLectura", SqlDbType.Int).Value = idLectura;
                c.Parameters.Add("@IdRecepcion", SqlDbType.Int).Value = idRecepcion;
            });
        }

        private static string Recortar(string s, int max)
        {
            if (s == null) return null;
            s = s.Trim();
            return s.Length <= max ? s : s.Substring(0, max);
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
