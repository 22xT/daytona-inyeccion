using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Pagos a proveedores (script 95): ordenes de pago que dicen que
       facturas cancelan, y los datos fiscales de cada factura de compra. */

    public class OPImputacion { public int IdMovimiento { get; set; } public decimal Importe { get; set; } }
    public class OPNotaCredito { public int IdNotaCredito { get; set; } public decimal Importe { get; set; } }
    public class OPMedio { public int IdCuentaFinanciera { get; set; } public decimal Importe { get; set; } public string Referencia { get; set; } }

    public class OrdenPagoDto
    {
        public int IdProveedor { get; set; }
        public List<OPImputacion> Facturas { get; set; }
        public List<OPNotaCredito> NotasCredito { get; set; }
        public List<OPMedio> Medios { get; set; }
        public string Observacion { get; set; }
    }

    public class CompraIva { public int IdArcaIva { get; set; } public decimal BaseImponible { get; set; } public decimal Importe { get; set; } }

    public class CompraFiscalDto
    {
        public int TipoArca { get; set; }
        public int PuntoVenta { get; set; }
        public long Numero { get; set; }
        public DateTime Fecha { get; set; }
        public string Cae { get; set; }
        public DateTime? CaeVencimiento { get; set; }
        public decimal ImporteNoGravado { get; set; }
        public decimal ImporteExento { get; set; }
        public decimal PercepcionIva { get; set; }
        public decimal PercepcionIibb { get; set; }
        public decimal ImpuestosInternos { get; set; }
        public decimal OtrosTributos { get; set; }
        public decimal ImporteTotal { get; set; }
        public List<CompraIva> Iva { get; set; }
    }

    public class OrdenPago
    {
        private readonly string _cnn = Config.Conexion;

        public DataTable Registrar(OrdenPagoDto d, int idUsuario)
        {
            DataTable imp = Tabla(new[] { "IdMovimiento:int", "Importe:dec" });
            foreach (OPImputacion i in d.Facturas ?? new List<OPImputacion>()) imp.Rows.Add(i.IdMovimiento, i.Importe);
            DataTable nc = Tabla(new[] { "IdNotaCredito:int", "Importe:dec" });
            foreach (OPNotaCredito n in d.NotasCredito ?? new List<OPNotaCredito>()) nc.Rows.Add(n.IdNotaCredito, n.Importe);
            DataTable med = Tabla(new[] { "IdCuentaFinanciera:int", "Importe:dec", "Referencia:str" });
            foreach (OPMedio m in d.Medios ?? new List<OPMedio>())
                med.Rows.Add(m.IdCuentaFinanciera, m.Importe, string.IsNullOrWhiteSpace(m.Referencia) ? (object)DBNull.Value : m.Referencia.Trim());

            return Ejecutar("SP_OrdenPago_I", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = d.IdProveedor;
                Tvp(c, "@Imputaciones", imp, "dbo.OPImputacionType");
                Tvp(c, "@NotasCredito", nc, "dbo.OPNotaCreditoType");
                Tvp(c, "@Medios", med, "dbo.OPMedioType");
                c.Parameters.Add("@Observacion", SqlDbType.NVarChar, 250).Value =
                    string.IsNullOrWhiteSpace(d.Observacion) ? (object)DBNull.Value : d.Observacion.Trim();
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        public void Anular(int id, string motivo, int idUsuario)
        {
            Ejecutar("SP_OrdenPago_Anular", c =>
            {
                c.Parameters.Add("@IdOrdenPago", SqlDbType.Int).Value = id;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = (object)motivo ?? DBNull.Value;
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        public DataTable Listar(int? idProveedor, DateTime? desde, DateTime? hasta)
        {
            return Ejecutar("SP_OrdenPago_GetAll", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor.HasValue ? (object)idProveedor.Value : DBNull.Value;
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = desde.HasValue ? (object)desde.Value.Date : DBNull.Value;
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = hasta.HasValue ? (object)hasta.Value.Date : DBNull.Value;
            }).Tables[0];
        }

        public DataSet Obtener(int id)
        {
            return Ejecutar("SP_OrdenPago_GetId", c => { c.Parameters.Add("@Id", SqlDbType.Int).Value = id; });
        }

        public DataTable NotasCreditoDisponibles(int idProveedor)
        {
            return Ejecutar("SP_NotaCreditoProveedor_Disponibles", c =>
            {
                c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor;
            }).Tables[0];
        }

        /* ---------- Datos fiscales de la compra ---------- */

        public DataSet FiscalObtener(int idMovimiento)
        {
            return Ejecutar("SP_CompraFiscal_Get", c => { c.Parameters.Add("@IdMovimiento", SqlDbType.Int).Value = idMovimiento; });
        }

        public DataTable FiscalEstado(int idProveedor)
        {
            return Ejecutar("SP_CompraFiscal_Estado", c => { c.Parameters.Add("@IdProveedor", SqlDbType.Int).Value = idProveedor; }).Tables[0];
        }

        public void FiscalGuardar(int idMovimiento, CompraFiscalDto d, int idUsuario)
        {
            DataTable iva = Tabla(new[] { "IdArcaIva:int", "BaseImponible:dec", "Importe:dec" });
            foreach (CompraIva i in d.Iva ?? new List<CompraIva>()) iva.Rows.Add(i.IdArcaIva, i.BaseImponible, i.Importe);

            Ejecutar("SP_CompraFiscal_Guardar", c =>
            {
                c.Parameters.Add("@IdMovimiento", SqlDbType.Int).Value = idMovimiento;
                c.Parameters.Add("@TipoArca", SqlDbType.Int).Value = d.TipoArca;
                c.Parameters.Add("@PuntoVenta", SqlDbType.Int).Value = d.PuntoVenta;
                c.Parameters.Add("@Numero", SqlDbType.BigInt).Value = d.Numero;
                c.Parameters.Add("@Fecha", SqlDbType.Date).Value = d.Fecha.Date;
                c.Parameters.Add("@Cae", SqlDbType.VarChar, 14).Value = string.IsNullOrWhiteSpace(d.Cae) ? (object)DBNull.Value : d.Cae.Trim();
                c.Parameters.Add("@CaeVencimiento", SqlDbType.Date).Value = d.CaeVencimiento.HasValue ? (object)d.CaeVencimiento.Value.Date : DBNull.Value;
                Dec(c, "@ImporteNoGravado", d.ImporteNoGravado);
                Dec(c, "@ImporteExento", d.ImporteExento);
                Dec(c, "@PercepcionIva", d.PercepcionIva);
                Dec(c, "@PercepcionIibb", d.PercepcionIibb);
                Dec(c, "@ImpuestosInternos", d.ImpuestosInternos);
                Dec(c, "@OtrosTributos", d.OtrosTributos);
                Dec(c, "@ImporteTotal", d.ImporteTotal);
                Tvp(c, "@Iva", iva, "dbo.CompraIvaType");
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            });
        }

        /* ---------- Utilidades ---------- */

        private static void Dec(SqlCommand c, string nombre, decimal valor)
        {
            SqlParameter p = c.Parameters.Add(nombre, SqlDbType.Decimal);
            p.Precision = 12; p.Scale = 2; p.Value = valor;
        }

        private static void Tvp(SqlCommand c, string nombre, DataTable t, string tipo)
        {
            SqlParameter p = c.Parameters.AddWithValue(nombre, t);
            p.SqlDbType = SqlDbType.Structured;
            p.TypeName = tipo;
        }

        // "Nombre:int|dec|str"
        private static DataTable Tabla(string[] columnas)
        {
            var t = new DataTable();
            foreach (string col in columnas)
            {
                string[] p = col.Split(':');
                Type tipo = p[1] == "int" ? typeof(int) : p[1] == "dec" ? typeof(decimal) : typeof(string);
                t.Columns.Add(p[0], tipo);
            }
            return t;
        }

        private DataSet Ejecutar(string sp, Action<SqlCommand> parametros)
        {
            using (var cnn = new SqlConnection(_cnn))
            using (var cmd = new SqlCommand(sp, cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                parametros(cmd);
                var ds = new DataSet();
                using (var da = new SqlDataAdapter(cmd)) { cnn.Open(); da.Fill(ds); }
                if (ds.Tables.Count == 0) ds.Tables.Add(new DataTable());
                return ds;
            }
        }
    }
}
