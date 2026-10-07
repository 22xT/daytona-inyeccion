using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

namespace WebApi.Models
{
    /* Devoluciones y notas de credito y debito a clientes. */

    public class DevolucionLinea
    {
        public int IdRepuesto { get; set; }
        public int Cantidad { get; set; }
        public bool ReingresaStock { get; set; }
    }

    public class NotaCreditoClienteDto
    {
        public int? IdVenta { get; set; }
        public int? IdCliente { get; set; }
        public List<DevolucionLinea> Lineas { get; set; }
        public decimal? ImporteSinDevolucion { get; set; }
        public string Motivo { get; set; }
        public string Resolucion { get; set; }        // CUENTA | REINTEGRO
        public int? IdCuentaReintegro { get; set; }
    }

    public class NotaDebitoClienteDto
    {
        public int IdCliente { get; set; }
        public decimal Importe { get; set; }
        public string Motivo { get; set; }
    }

    public class NotaCliente
    {
        private string connectionstring = Config.Conexion;
        private static object N(object v) { return v ?? DBNull.Value; }

        public DataSet ParaDevolucion(int idVenta)
        {
            return Consultar("SP_Venta_ParaDevolucion", c => c.Parameters.Add("@IdVenta", SqlDbType.Int).Value = idVenta);
        }

        public DataTable Credito(NotaCreditoClienteDto d, int idUsuario)
        {
            DataTable t = new DataTable();
            t.Columns.Add("IdRepuesto", typeof(int));
            t.Columns.Add("Cantidad", typeof(int));
            t.Columns.Add("ReingresaStock", typeof(bool));
            if (d.Lineas != null)
                foreach (DevolucionLinea l in d.Lineas)
                    if (l.Cantidad > 0) t.Rows.Add(l.IdRepuesto, l.Cantidad, l.ReingresaStock);

            return Consultar("SP_NotaCreditoCliente_I", c =>
            {
                c.Parameters.Add("@IdVenta", SqlDbType.Int).Value = N(d.IdVenta);
                c.Parameters.Add("@IdCliente", SqlDbType.Int).Value = N(d.IdCliente);
                SqlParameter p = c.Parameters.AddWithValue("@Lineas", t);
                p.SqlDbType = SqlDbType.Structured; p.TypeName = "dbo.DevolucionLineaType";
                c.Parameters.Add("@ImporteSinDevolucion", SqlDbType.Decimal).Value = N(d.ImporteSinDevolucion);
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(d.Motivo);
                c.Parameters.Add("@Resolucion", SqlDbType.VarChar, 10).Value = N(d.Resolucion);
                c.Parameters.Add("@IdCuentaReintegro", SqlDbType.Int).Value = N(d.IdCuentaReintegro);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0];
        }

        public int Debito(NotaDebitoClienteDto d, int idUsuario)
        {
            return Convert.ToInt32(Consultar("SP_NotaDebitoCliente_I", c =>
            {
                c.Parameters.Add("@IdCliente", SqlDbType.Int).Value = d.IdCliente;
                c.Parameters.Add("@Importe", SqlDbType.Decimal).Value = d.Importe;
                c.Parameters.Add("@Motivo", SqlDbType.NVarChar, 250).Value = N(d.Motivo);
                c.Parameters.Add("@IdUsuario", SqlDbType.Int).Value = idUsuario;
            }).Tables[0].Rows[0]["IdNota"]);
        }

        public DataTable Listar(DateTime? desde, DateTime? hasta)
        {
            return Consultar("SP_NotaCliente_GetAll", c =>
            {
                c.Parameters.Add("@Desde", SqlDbType.Date).Value = N(desde);
                c.Parameters.Add("@Hasta", SqlDbType.Date).Value = N(hasta);
            }).Tables[0];
        }

        // Tira error si la venta ya no se puede anular (otro dia, caja cerrada, con nota)
        public void ValidarAnulacionVenta(int idVenta)
        {
            using (SqlConnection cnn = new SqlConnection(connectionstring))
            using (SqlCommand cmd = new SqlCommand("SP_Venta_ValidarAnulacion", cnn))
            {
                cmd.CommandType = CommandType.StoredProcedure;
                cmd.Parameters.Add("@IdVenta", SqlDbType.Int).Value = idVenta;
                cnn.Open();
                cmd.ExecuteNonQuery();
            }
        }

        private DataSet Consultar(string sp, Action<SqlCommand> parametros)
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
    }
}
