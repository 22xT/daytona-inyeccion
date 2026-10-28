(function () {
  'use strict';

  // ==========================================================
  // AREAS — el sistema se ordena en areas del negocio.
  // Al entrar se elige un area (Index.html); adentro de una pantalla
  // la barra muestra SOLO las opciones de su area.
  // Para mover una pantalla de lugar, basta con cambiarla de area aca.
  //   href:    la pantalla
  //   tambien: otras pantallas que pertenecen a esa opcion (formularios)
  //   desc:    la bajada de la tarjeta en la pantalla del area
  // color: el color que identifica al area (tarjeta, pestañas y pantalla del area)
  // ==========================================================
  var TODOS = ['Dueño', 'Administrador', 'Supervisor', 'Vendedor', 'Analista'];
  var AREAS = [
    {
      key: 'ventas', titulo: 'Ventas', bajada: 'El mostrador: buscar, vender, presupuestar, encargar y atender a los clientes.',
      icon: 'bi-shop', color: '#b91c1c',
      items: [
        { key: 'venta-nueva', label: 'Venta', icon: 'bi-cart-plus', href: 'CargarVenta.html',
          desc: 'Cargar la venta y cobrarla.', roles: ['Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'buscador', label: 'Buscador', icon: 'bi-search', href: 'Buscador.html',
          desc: 'Lo que tengo y lo que consigo.', roles: TODOS },
        { key: 'presupuestos', label: 'Presupuestos', icon: 'bi-file-earmark-text', href: 'ListadoPresupuestos.html',
          desc: 'Cotizarle al cliente y pasarlo a venta.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'encargos', label: 'Encargos', icon: 'bi-bookmark-star', href: 'Encargos.html',
          desc: 'Lo que el cliente pidió y no hay, con seña.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'clientes', label: 'Clientes', icon: 'bi-people', href: 'ClientesListado.html', tambien: ['ClienteForm.html'],
          desc: 'Datos, mecánicos y su historial.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'ventas', label: 'Ventas y devoluciones', icon: 'bi-receipt', href: 'ListadoVentas.html', tambien: ['DevolucionVenta.html'],
          desc: 'Listado, anulaciones y notas de crédito.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] }
      ]
    },
    {
      key: 'compras', titulo: 'Compras', bajada: 'Qué falta, a quién pedírselo y seguir el pedido hasta que llega.',
      icon: 'bi-truck', color: '#1d5fa8',
      items: [
        { key: 'pedido-nuevo', label: 'Reposición sugerida', icon: 'bi-stars', href: 'PedidoNuevo.html',
          desc: 'Lo que se está acabando.', roles: ['Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'carrito', label: 'Carrito', icon: 'bi-cart', href: 'Carrito.html',
          desc: 'Elegir el proveedor y confirmar.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'pedido-manual', label: 'Pedido manual', icon: 'bi-pencil-square', href: 'PedidoManual.html',
          desc: 'Para proveedores sin lista.', roles: ['Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'pedidos', label: 'Pedidos', icon: 'bi-clipboard-data', href: 'ListadoPedido.html', tambien: ['RecepcionPedido.html'],
          desc: 'Enviar, recibir y reclamar.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'proveedores', label: 'Proveedores', icon: 'bi-building', href: 'ProveedoresListado.html', tambien: ['ProveedorForm.html'],
          desc: 'Datos, condiciones y plazos.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'listas-precios', label: 'Listas de precios', icon: 'bi-file-earmark-arrow-up', href: 'ListasPrecios.html',
          desc: 'La actualización de los viernes.', roles: ['Dueño', 'Administrador'] },
        { key: 'catalogo-proveedores', label: 'Catálogo de proveedores', icon: 'bi-search', href: 'CatalogoProveedores.html',
          desc: 'Todo lo que se consigue.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'matcher', label: 'Relacionar repuestos', icon: 'bi-diagram-3', href: 'Matcher.html',
          desc: 'Iguales y equivalentes entre marcas.', roles: ['Dueño', 'Administrador'] }
      ]
    },
    {
      key: 'inventario', titulo: 'Inventario', bajada: 'Lo que hay en el local: stock, conteo y ajustes.',
      icon: 'bi-box-seam', color: '#0f766e',
      items: [
        { key: 'repuestos-stock', label: 'Stock', icon: 'bi-box-seam', href: 'StockRepuestos.html', tambien: ['CargarRepuesto.html'],
          desc: 'Cantidades, mínimos y fichas.', roles: TODOS },
        { key: 'ajuste-stock', label: 'Ajuste de stock', icon: 'bi-sliders', href: 'AjusteStock.html',
          desc: 'Corregir con motivo.', roles: ['Administrador', 'Analista', 'Vendedor'] },
        { key: 'inventario', label: 'Inventario físico', icon: 'bi-clipboard-check', href: 'InventarioFisico.html',
          desc: 'Contar sin ver lo que dice el sistema.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'rubros', label: 'Rubros', icon: 'bi-folder2-open', href: 'RubrosListado.html', tambien: ['RubroForm.html'],
          desc: 'Cómo se ordena el catálogo.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'marcas', label: 'Marcas', icon: 'bi-tag', href: 'MarcasListado.html', tambien: ['MarcaForm.html'],
          desc: 'Marcas de vehículos.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'modelos', label: 'Modelos', icon: 'bi-car-front', href: 'ModelosListado.html', tambien: ['ModeloForm.html'],
          desc: 'Modelos por marca.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] }
      ]
    },
    {
      key: 'administracion', titulo: 'Administración', bajada: 'La plata del negocio: caja, cobros, pagos, gastos y configuración.',
      icon: 'bi-cash-coin', color: '#6b3fa0',
      items: [
        { key: 'caja', label: 'Caja', icon: 'bi-cash-stack', href: 'Caja.html',
          desc: 'Abrir, cerrar y arqueo.', roles: ['Dueño', 'Administrador', 'Vendedor'] },
        { key: 'comprobantes', label: 'Comprobantes', icon: 'bi-file-earmark-text', href: 'Comprobantes.html',
          desc: 'Facturas y notas de crédito y débito.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'movimientos-especiales', label: 'Movimientos especiales', icon: 'bi-arrow-left-right', href: 'MovimientosEspeciales.html',
          desc: 'Aportes, retiros y transferencias.', roles: ['Dueño', 'Administrador', 'Analista'] },
        { key: 'gastos', label: 'Gastos', icon: 'bi-receipt-cutoff', href: 'Gastos.html',
          desc: 'Con comprobante adjunto.', roles: ['Dueño', 'Administrador', 'Analista'] },
        { key: 'cuentacorriente', label: 'Cuenta corriente de clientes', icon: 'bi-journal-text', href: 'CuentaCorriente.html',
          desc: 'Lo que deben los mecánicos.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'cuenta-proveedores', label: 'Cuenta de proveedores', icon: 'bi-journal-bookmark', href: 'CuentaProveedores.html',
          desc: 'Facturas a pagar y pagos.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'configuracion', label: 'Configuración comercial', icon: 'bi-percent', href: 'Configuracion.html',
          desc: 'Márgenes, descuentos y parámetros.', roles: ['Dueño', 'Administrador'] },
        { key: 'auditoria', label: 'Auditoría', icon: 'bi-shield-check', href: 'Auditoria.html',
          desc: 'Quién cambió qué y cuándo.', roles: ['Dueño', 'Administrador'] }
      ]
    },
    {
      key: 'reportes', titulo: 'Reportes', bajada: 'El tablero y la información para decidir.',
      icon: 'bi-graph-up-arrow', color: '#b45309',
      items: [
        { key: 'dashboard', label: 'Tablero', icon: 'bi-speedometer2', href: 'Dashboard.html', tambien: ['Tablero.html'],
          desc: 'Cómo viene el negocio y qué conviene hacer.', roles: ['Dueño', 'Administrador', 'Supervisor'] },
        { key: 'rep-ventas', label: 'Ventas por período', icon: 'bi-graph-up', href: 'ReporteVentas.html',
          desc: 'Ventas, ganancia y pronóstico.', roles: ['Dueño', 'Administrador', 'Supervisor'] },
        { key: 'rep-caja', label: 'Resumen de caja', icon: 'bi-cash-coin', href: 'ReporteCaja.html',
          desc: 'Ingresos y egresos por medio.', roles: ['Dueño', 'Administrador'] },
        { key: 'rep-stock', label: 'Stock crítico', icon: 'bi-exclamation-triangle', href: 'ReporteStockCritico.html',
          desc: 'Lo que está por debajo del mínimo.', roles: TODOS },
        { key: 'rep-busquedas', label: 'Búsquedas', icon: 'bi-search-heart', href: 'ReporteBusquedas.html',
          desc: 'Qué piden los clientes y no tenemos.', roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] }
      ]
    },
    {
      key: 'canales', titulo: 'Canales', bajada: 'Vender afuera del local: publicar el catálogo, responder consultas y cobrar con link de pago.',
      icon: 'bi-chat-dots', color: '#5b6878', proximamente: true,
      items: []
    }
  ];

  // Poco uso: van en el engranaje de la barra, no ocupan un area
  var SISTEMA = {
    key: 'sistema', titulo: 'Sistema', bajada: 'Usuarios, roles y estados.', icon: 'bi-gear',
    items: [
      { key: 'usuarios', label: 'Usuarios', icon: 'bi-people-fill', href: 'UsuariosListado.html', tambien: ['UsuarioForm.html'],
        desc: 'Altas, permisos y claves.', roles: ['Administrador'] },
      { key: 'roles', label: 'Roles', icon: 'bi-shield-lock-fill', href: 'RolesListado.html', tambien: ['RolForm.html'],
        desc: 'Qué puede hacer cada rol.', roles: ['Administrador'] },
      { key: 'estados-venta', label: 'Estados de venta', icon: 'bi-tags', href: 'EstadosVentaListado.html', tambien: ['EstadoVentaForm.html'],
        desc: 'Estados posibles de una venta.', roles: ['Administrador'] },
      { key: 'estados-pedido', label: 'Estados de pedido', icon: 'bi-tags-fill', href: 'EstadosPedidoListado.html', tambien: ['EstadoPedidoForm.html'],
        desc: 'Estados posibles de un pedido.', roles: ['Administrador'] }
    ]
  };

  // Lo que puede vender: el boton "Venta" queda fijo en la barra

  function archivoActual() {
    var f = (location.pathname.split('/').pop() || 'index.html');
    return f.toLowerCase();
  }

  // En que area esta una pantalla (por su archivo; si no, por data-page)
  function areaDePagina(archivo, activeKey) {
    archivo = (archivo || '').toLowerCase();
    if (archivo === 'area.html') {
      var m = /[?&]a=([a-z]+)/.exec(location.search);
      var a = m ? buscarArea(m[1]) : null;
      return a ? { area: a, item: null } : null;
    }
    var todas = AREAS.concat([SISTEMA]);
    for (var i = 0; i < todas.length; i++) {
      for (var j = 0; j < todas[i].items.length; j++) {
        var it = todas[i].items[j];
        var hrefs = [it.href].concat(it.tambien || []).map(function (h) { return h.toLowerCase(); });
        if (hrefs.indexOf(archivo) !== -1) return { area: todas[i], item: it };
      }
    }
    for (var x = 0; x < todas.length; x++)
      for (var y = 0; y < todas[x].items.length; y++)
        if (activeKey && todas[x].items[y].key === activeKey) return { area: todas[x], item: todas[x].items[y] };
    return null;
  }

  function buscarArea(key) {
    if (key === 'sistema') return SISTEMA;
    for (var i = 0; i < AREAS.length; i++) if (AREAS[i].key === key) return AREAS[i];
    return null;
  }

  // Areas con algo que el rol pueda abrir (Canales se muestra igual: es "proximamente")
  function areasVisibles(rolUsuario) {
    return AREAS.filter(function (a) {
      return a.proximamente || itemsVisibles(a, rolUsuario).length > 0;
    });
  }

  // Roles que ven la campanita de notificaciones
  var ROLES_NOTIFICACIONES = ['Dueño', 'Administrador'];

  var POLLING_MS = 30000; // refresco cada 30 seg
  var intervaloNotif = null;

  function escape(s) {
    if (s === null || s === undefined) return '';
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function tieneRol(rolUsuario, rolesPermitidos) {
    if (!rolesPermitidos || rolesPermitidos.length === 0) return true;
    if (!rolUsuario) return false;
    return rolesPermitidos.indexOf(rolUsuario) !== -1;
  }

  // Paginas de una seccion que el rol actual puede ver
  function itemsVisibles(group, rolUsuario) {
    return group.items.filter(function (it) { return tieneRol(rolUsuario, it.roles); });
  }

  function iniciales(nombre) {
    if (!nombre) return '?';
    var partes = String(nombre).trim().split(/\s+/);
    var ini = partes[0].charAt(0);
    if (partes.length > 1) ini += partes[partes.length - 1].charAt(0);
    return ini.toUpperCase();
  }

  /* ============ RENDER DE LA BARRA SUPERIOR ============
     Afuera de un area (inicio): marca, Venta, campanita, usuario.
     Adentro de un area: ademas, "Areas", el nombre del area con un
     desplegable para saltar a otra, y SOLO las opciones de esa area. */

  function renderTopbar(activeKey) {
    var container = document.getElementById('sidebar-container');
    if (!container) return;

    var usuario = (window.Auth && Auth.getUsuario()) ? Auth.getUsuario() : null;
    var rolUsuario = usuario ? usuario.Rol : null;
    var donde = areaDePagina(archivoActual(), activeKey);
    // El color del area pinta la pantalla (encabezado, iconos de paneles):
    // asi cada modulo se distingue de un vistazo (devolucion 28/10)
    if (donde && donde.area.color) {
      document.documentElement.style.setProperty('--area', donde.area.color);
      document.body.setAttribute('data-area', donde.area.key);
    }

    var html = '<header class="topbar"><div class="topbar-inner">';

    html += '<a class="topbar-brand" href="index.html" title="Inicio">' +
      '<i class="bi bi-flag-fill"></i>' +
      '<span class="marca">' +
        '<span class="marca-nombre">DAYTONA</span>' +
        '<span class="marca-bajada">REPUESTOS AUTOMOTOR</span>' +
      '</span></a>';

    if (donde) {
      var area = donde.area;
      html += '<div class="area-nav">';
      html += '<a class="btn-areas" href="index.html" title="Volver a las áreas"><i class="bi bi-grid"></i><span>Áreas</span></a>';
      html += '<div class="topnav-item area-switch" data-menu="areas">';
      html += '<button type="button" class="area-actual" onclick="Layout.toggleMenu(\'areas\')">' +
        '<span class="area-punto" style="background:' + (area.color || '#d92020') + '"></span>' +
        '<i class="bi ' + area.icon + '"></i>' + escape(area.titulo) + '<i class="bi bi-chevron-down chev"></i></button>';
      html += '<div class="topnav-menu">';
      areasVisibles(rolUsuario).forEach(function (a) {
        var cls = a.key === area.key ? ' active' : '';
        html += '<a href="Area.html?a=' + a.key + '" class="topnav-menu-item' + cls + '">' +
          '<i class="bi ' + a.icon + '" style="color:' + (a.color || '#6c7a89') + '"></i> ' + escape(a.titulo) +
          (a.proximamente ? '<span class="pronto">pronto</span>' : '') +
          '<span class="nav-area-num" data-area-globo="' + a.key + '"></span></a>';
      });
      html += '</div></div></div>';

      html += '<button type="button" class="topbar-burger" onclick="Layout.toggleBurger()" ' +
        'aria-label="Opciones de ' + escape(area.titulo) + '"><i class="bi bi-list"></i></button>';

      html += '<div class="topbar-espacio"></div>';
    } else {
      html += '<div class="topbar-espacio"></div>';
    }

    html += '<div class="topbar-right" id="topbar-right">';
    var sistema = itemsVisibles(SISTEMA, rolUsuario);
    if (sistema.length) {
      html += '<div class="topnav-item" data-menu="sistema">';
      html += '<button type="button" class="btn-redondo" title="Sistema" aria-label="Sistema" onclick="Layout.toggleMenu(\'sistema\')"><i class="bi bi-gear"></i></button>';
      html += '<div class="topnav-menu align-right">';
      sistema.forEach(function (it) {
        var cls = donde && donde.item && donde.item.key === it.key ? ' active' : '';
        html += '<a href="' + it.href + '" class="topnav-menu-item' + cls + '"><i class="bi ' + it.icon + '"></i> ' + escape(it.label) + '</a>';
      });
      html += '</div></div>';
    }
    if (usuario) {
      html += '<div class="topnav-item user-menu" data-menu="usuario">';
      html += '<button type="button" class="user-btn" onclick="Layout.toggleMenu(\'usuario\')">';
      html += '<span class="user-avatar">' + escape(iniciales(usuario.Nombre)) + '</span>';
      html += '<span class="user-info">';
      html += '<span class="user-name">' + escape(usuario.Nombre) + '</span>';
      html += '<span class="user-role">' + escape(usuario.Rol) + '</span>';
      html += '</span>';
      html += '<i class="bi bi-chevron-down chev"></i>';
      html += '</button>';
      html += '<div class="topnav-menu align-right">';
      html += '<div class="user-menu-head">' +
        '<div class="nombre">' + escape(usuario.Nombre) + '</div>' +
        '<div class="rol"><i class="bi bi-shield-check"></i> ' + escape(usuario.Rol) + '</div></div>';
      html += '<a href="javascript:void(0)" class="topnav-menu-item salir" onclick="Auth.logout()">' +
        '<i class="bi bi-box-arrow-right"></i> Cerrar sesión</a>';
      html += '</div></div>';
    }
    html += '</div>';

    html += '</div>';

    // Segunda fila: SOLO las opciones del area
    if (donde && donde.area.items.length) {
      html += '<nav class="area-tabs-bar" id="topnav" style="--ac:' + (donde.area.color || '#d92020') + '" aria-label="' + escape(donde.area.titulo) + '"><div class="area-tabs-inner">';
      itemsVisibles(donde.area, rolUsuario).forEach(function (it) {
        var activo = donde.item && donde.item.key === it.key;
        html += '<a href="' + it.href + '" class="area-tab' + (activo ? ' active' : '') + '"' +
          (activo ? ' aria-current="page"' : '') + '>' +
          '<i class="bi ' + it.icon + '"></i><span>' + escape(it.label) + '</span></a>';
      });
      html += '</div></nav>';
    }

    html += '</header>';
    container.innerHTML = html;
  }

  function cerrarMenus(excepto) {
    var abiertos = document.querySelectorAll('.topnav-item.open');
    for (var i = 0; i < abiertos.length; i++) {
      if (abiertos[i].getAttribute('data-menu') !== excepto) {
        abiertos[i].classList.remove('open');
      }
    }
  }

  function toggleMenu(menuKey) {
    var item = document.querySelector('.topnav-item[data-menu="' + menuKey + '"]');
    if (!item) return;
    var estaAbierto = item.classList.contains('open');
    cerrarMenus(null);
    if (!estaAbierto) item.classList.add('open');
  }

  function toggleBurger() {
    var nav = document.getElementById('topnav');
    if (nav) nav.classList.toggle('abierto');
  }

  // Cerrar los desplegables al cliquear afuera o con Escape
  function engancharCierres() {
    document.addEventListener('click', function (e) {
      if (e.target.closest && e.target.closest('.topnav-item')) return;
      cerrarMenus(null);
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') cerrarMenus(null);
    });
  }

  /* ============ ESTILOS DE LA BARRA ============ */

  function cargarFuenteLogo() {
    if (document.getElementById('font-logo-daytona')) return;
    var pre = document.createElement('link');
    pre.rel = 'preconnect';
    pre.href = 'https://fonts.gstatic.com';
    pre.crossOrigin = 'anonymous';
    document.head.appendChild(pre);

    var link = document.createElement('link');
    link.id = 'font-logo-daytona';
    link.rel = 'stylesheet';
    link.href = 'https://fonts.googleapis.com/css2?family=Archivo+Black&display=swap';
    document.head.appendChild(link);
  }

  function inyectarEstilos() {
    if (document.getElementById('layout-extra-styles')) return;
    cargarFuenteLogo();
    var css = ''
      /* ---- Barra superior ---- */
      + '.topbar{position:sticky;top:0;z-index:1040;background:#fff;border-bottom:1px solid #e3e7ec;box-shadow:0 1px 6px rgba(0,0,0,0.05);}'
      + '.topbar-inner{display:flex;align-items:stretch;gap:6px;padding:0 20px;min-height:70px;}'
      + '.topbar-brand{display:flex;align-items:center;gap:9px;text-decoration:none;color:#001f3f;font-weight:700;font-size:1.15rem;padding-right:16px;margin-right:6px;border-right:1px solid #e3e7ec;flex-shrink:0;}'
      + '.topbar-brand:hover{color:#001f3f;}'
      + '.topbar-brand i{color:var(--nav-accent);font-size:1.6rem;}'
      // .topbar-brand delante: algunas pantallas tienen su propia clase .marca (chips de marca)
      + '.topbar-brand .marca{display:flex;flex-direction:column;line-height:1;background:none;border:0;padding:0;margin:0;border-radius:0;color:inherit;font-size:inherit;font-weight:inherit;}'
      + '.marca-nombre{font-family:"Archivo Black","Arial Black",Impact,sans-serif;'
      +   'font-size:1.42rem;letter-spacing:-0.5px;color:#001f3f;'
      +   'transform:skewX(-8deg);transform-origin:left bottom;}'
      + '.marca-bajada{font-size:0.53rem;letter-spacing:2.1px;color:#6c7a89;'
      +   'font-weight:700;margin-top:3px;}'
      + '@media (max-width:1100px){.marca-nombre{font-size:1.2rem;}.marca-bajada{letter-spacing:1.2px;}}'

      /* ---- Items de navegacion ---- */
      + '.topnav{display:flex;align-items:stretch;flex:1;gap:2px;overflow:visible;justify-content:space-evenly;}'
      + '.topnav-item{position:relative;display:flex;}'
      + '.topnav-link{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1px;'
      +   'padding:9px 20px 7px;background:none;border:none;border-bottom:3px solid transparent;'
      +   'color:#2c3e50;text-decoration:none;cursor:pointer;font-family:inherit;transition:0.15s;white-space:nowrap;}'
      + '.topnav-link:hover{background:#f4f6f8;color:#001f3f;}'
      + '.topnav-link .ico{font-size:1.45rem;line-height:1;}'
      + '.topnav-link .lbl{display:flex;align-items:center;gap:5px;font-size:1rem;font-weight:500;}'
      + '.topnav-link .chev{font-size:0.68rem;opacity:0.55;transition:transform 0.15s;}'
      + '.topnav-item.open .topnav-link .chev{transform:rotate(180deg);}'
      + '.topnav-link.active{color:var(--nav-accent-dark);font-weight:600;border-bottom-color:var(--nav-accent);}'
      + '.topnav-link.active .ico{color:var(--nav-accent);}'
      /* Globo de aviso sobre el icono de la seccion */
      + '.topnav-link{position:relative;}'
      + '.nav-globo{position:absolute;top:2px;right:6px;background:#ff3333;color:#fff;'
      +   'border-radius:10px;min-width:18px;height:18px;font-size:0.66rem;font-weight:700;'
      +   'display:flex;align-items:center;justify-content:center;padding:0 5px;'
      +   'box-shadow:0 1px 4px rgba(255,51,51,0.45);}'
      + '.nav-globo.suave{background:#c47700;box-shadow:0 1px 4px rgba(196,119,0,0.4);}'
      + '.topnav-item.open .topnav-link{background:#f4f6f8;}'

      /* ---- Desplegables ---- */
      + '.topnav-menu{display:none;position:absolute;top:100%;left:0;min-width:248px;background:#fff;'
      +   'border:1px solid #e3e7ec;border-radius:0 0 10px 10px;box-shadow:0 10px 30px rgba(0,0,0,0.13);'
      +   'padding:6px;z-index:1050;animation:tbDrop 0.15s ease-out;}'
      + '.topnav-menu.align-right{left:auto;right:0;border-radius:10px;}'
      + '.topnav-item.open .topnav-menu{display:block;}'
      + '@keyframes tbDrop{from{opacity:0;transform:translateY(-6px);}to{opacity:1;transform:translateY(0);}}'
      + '.topnav-menu-item{display:flex;align-items:center;gap:10px;padding:10px 13px;border-radius:7px;'
      +   'color:#2c3e50;text-decoration:none;font-size:0.93rem;transition:0.12s;}'
      + '.topnav-menu-item:hover{background:#f4f6f8;color:#001f3f;}'
      + '.topnav-menu-item i{font-size:0.95rem;color:#6c7a89;width:18px;text-align:center;}'
      + '.topnav-menu-item.active{background:var(--nav-accent-soft);color:var(--nav-accent-dark);font-weight:600;}'
      + '.topnav-menu-item.active i{color:var(--nav-accent);}'
      + '.topnav-menu-item.salir{color:#d92020;}'
      + '.topnav-menu-item.salir:hover{background:#ffeded;color:#d92020;}'
      + '.topnav-menu-item.salir i{color:#d92020;}'

      /* ---- Bloque de usuario (derecha) ---- */
      + '.topbar-right{display:flex;align-items:center;gap:10px;padding-left:14px;margin-left:auto;'
      +   'border-left:1px solid #e3e7ec;flex-shrink:0;}'
      + '.user-btn{display:flex;align-items:center;gap:9px;background:none;border:1px solid transparent;'
      +   'border-radius:9px;padding:5px 10px;cursor:pointer;font-family:inherit;transition:0.15s;}'
      + '.user-btn:hover{background:#f4f6f8;border-color:#e3e7ec;}'
      + '.user-avatar{width:34px;height:34px;border-radius:50%;background:#001f3f;color:#fff;'
      +   'display:flex;align-items:center;justify-content:center;font-size:0.8rem;font-weight:700;flex-shrink:0;}'
      + '.user-info{display:flex;flex-direction:column;align-items:flex-start;line-height:1.15;}'
      + '.user-btn .user-name{font-size:0.85rem;font-weight:600;color:#2c3e50;}'
      + '.user-btn .user-role{font-size:0.7rem;color:#fff;background:var(--nav-accent);padding:1px 8px;'
      +   'border-radius:9px;font-weight:600;letter-spacing:0.2px;margin-top:2px;}'
      + '.user-btn .chev{font-size:0.62rem;color:#6c7a89;}'
      + '.user-menu-head{padding:10px 12px 9px;border-bottom:1px solid #e3e7ec;margin-bottom:5px;}'
      + '.user-menu-head .nombre{font-weight:700;color:#001f3f;font-size:0.9rem;}'
      + '.user-menu-head .rol{font-size:0.76rem;color:#6c7a89;margin-top:3px;display:flex;align-items:center;gap:5px;}'
      + '.user-menu-head .rol i{color:var(--nav-accent);}'

      /* ---- Boton hamburguesa (pantallas chicas) ---- */
      + '.topbar-burger{display:none;background:none;border:none;font-size:1.6rem;color:#001f3f;cursor:pointer;padding:0 10px;}'

      /* ---- Campanita, ahora dentro de la barra ---- */
      + '.notif-bell-wrapper{position:relative;}'
      + '.notif-bell{position:relative;background:#fff;color:#001f3f;border:1px solid #e3e7ec;border-radius:50%;width:40px;height:40px;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:1.05rem;transition:all 0.2s;}'
      + '.notif-bell:hover{background:#f4f6f8;}'
      + '.notif-bell .badge-bell{position:absolute;top:-4px;right:-4px;background:#ff3333;color:#fff;border-radius:50%;min-width:20px;height:20px;font-size:0.68rem;font-weight:700;display:flex;align-items:center;justify-content:center;padding:0 5px;box-shadow:0 2px 6px rgba(255,51,51,0.4);animation:pulseBell 2s infinite;}'
      + '@keyframes pulseBell{0%{box-shadow:0 2px 6px rgba(255,51,51,0.4);transform:scale(1);}50%{box-shadow:0 2px 14px rgba(255,51,51,0.8);transform:scale(1.1);}100%{box-shadow:0 2px 6px rgba(255,51,51,0.4);transform:scale(1);}}'

      /* Panel de notificaciones */
      + '.notif-panel{position:absolute;top:52px;right:0;width:380px;max-height:540px;background:#fff;border:1px solid #e3e7ec;border-radius:12px;box-shadow:0 12px 40px rgba(0,0,0,0.15);display:none;overflow:hidden;animation:tbDrop 0.2s ease-out;z-index:1050;}'
      + '.notif-panel.open{display:flex;flex-direction:column;}'
      + '.notif-panel .head{padding:14px 18px;background:linear-gradient(135deg,#001f3f 0%,#0a3a6e 100%);color:#fff;font-weight:600;display:flex;justify-content:space-between;align-items:center;}'
      + '.notif-panel .head i{color:#ff6b6b;}'
      + '.notif-panel .body{padding:8px 0;overflow-y:auto;flex:1;}'
      + '.notif-section{padding:6px 0;}'
      + '.notif-section-title{padding:8px 18px 4px;font-size:0.7rem;font-weight:700;text-transform:uppercase;color:#6c7a89;letter-spacing:0.6px;}'
      + '.notif-item{display:flex;gap:10px;padding:10px 18px;border-bottom:1px solid #f0f2f5;font-size:0.85rem;color:#2c3e50;transition:background 0.15s;cursor:pointer;text-decoration:none;}'
      + '.notif-item:last-child{border-bottom:none;}'
      + '.notif-item:hover{background:#f8f9fa;color:#2c3e50;text-decoration:none;}'
      + '.notif-item .icon-circle{width:34px;height:34px;border-radius:50%;background:#ffeded;color:#ff3333;display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:0.95rem;}'
      + '.notif-item.amarillo .icon-circle{background:#fff9e6;color:#b58105;}'
      + '.notif-item.azul .icon-circle{background:#e7f1ff;color:#0d6efd;}'
      + '.notif-item.verde .icon-circle{background:#e6f7eb;color:#28a745;}'
      + '.notif-item .info{flex:1;min-width:0;}'
      + '.notif-item .info .title{font-weight:600;color:#001f3f;}'
      + '.notif-item .info .meta{font-size:0.76rem;color:#6c7a89;margin-top:2px;}'
      + '.notif-empty{padding:40px 20px;text-align:center;color:#6c7a89;}'
      + '.notif-empty i{font-size:3rem;opacity:0.3;display:block;margin-bottom:8px;color:#001f3f;}'
      + '.notif-loading{padding:30px;text-align:center;color:#6c7a89;font-size:0.85rem;}'

      /* ---- Responsive: menu vertical con hamburguesa ---- */
      + '@media (max-width:1400px){.topnav-link{padding:9px 10px 7px;}.topnav-link .lbl{font-size:0.88rem;}'
      +   '.topnav-link .ico{font-size:1.3rem;}}'
      // Con 9 secciones: en notebooks chicas el nombre del usuario se ve al abrir su menu
      + '@media (max-width:1320px){.user-btn .user-info{display:none;}}'
      + '@media (max-width:1150px){.topnav{justify-content:flex-start;}'
      +   '.topnav-link{padding:8px 10px 6px;}.topnav-link .lbl{font-size:0.83rem;}'
      +   '.user-btn .user-info{display:none;}}'
      + '@media (max-width:900px){'
      +   '.topbar-inner{flex-wrap:wrap;min-height:58px;}'
      +   '.topbar-burger{display:block;order:2;margin-left:auto;}'
      +   '.topbar-right{order:3;margin-left:8px;border-left:none;}'
      +   '.topnav{order:4;flex-basis:100%;display:none;flex-direction:column;align-items:stretch;'
      +     'border-top:1px solid #e3e7ec;padding:6px 0;}'
      +   '.topnav.abierto{display:flex;}'
      +   '.topnav-item{display:block;}'
      +   '.topnav-link{flex-direction:row;justify-content:flex-start;gap:9px;width:100%;'
      +     'padding:10px 12px;border-bottom:none;border-left:3px solid transparent;}'
      +   '.topnav-link.active{border-left-color:var(--nav-accent);background:var(--nav-accent-soft);}'
      +   '.topnav-link .chev{margin-left:auto;}'
      +   '.topnav-menu{position:static;box-shadow:none;border:none;border-left:2px solid #e3e7ec;'
      +     'margin-left:22px;border-radius:0;animation:none;min-width:0;}'
      +   '.notif-panel{width:calc(100vw - 28px);right:-8px;}}'
      /* ==== Barra por areas (27/10): azul marino, solo las opciones del area ==== */
      + '.topbar{background:#001f3f;border-bottom:none;box-shadow:0 2px 10px rgba(0,15,35,0.25);}'
      + '.topbar-inner{min-height:62px;gap:10px;}'
      + '.topbar-brand{border-right:1px solid #23466e;color:#fff;}'
      + '.topbar-brand:hover{color:#fff;}'
      + '.topbar-brand i{color:#ff3b3b;}'
      + '.marca-nombre{color:#fff;}'
      + '.marca-bajada{color:#a9bdd6;}'
      + '.topbar-espacio{flex:1;}'
      + '.area-nav{display:flex;align-items:center;gap:8px;padding-right:10px;flex-shrink:0;}'
      + '.btn-areas{display:flex;align-items:center;gap:6px;color:#c9d6e6;text-decoration:none;border:1px solid #2c5280;'
      +   'border-radius:20px;padding:5px 12px;font-size:0.85rem;font-weight:600;transition:0.15s;}'
      + '.btn-areas:hover{color:#fff;background:rgba(255,255,255,0.08);}'
      + '.area-switch{align-items:center;}'
      + '.area-actual{display:flex;align-items:center;gap:7px;background:none;border:none;color:#fff;font-family:inherit;'
      +   'font-size:1.08rem;font-weight:700;padding:6px 8px;border-radius:8px;cursor:pointer;}'
      + '.area-actual:hover{background:rgba(255,255,255,0.08);}'
      + '.area-actual .chev{font-size:0.65rem;opacity:0.7;}'
      + '.area-switch .topnav-menu{top:calc(100% + 10px);border-radius:10px;}'
      + '.pronto{margin-left:auto;font-size:0.68rem;font-weight:700;background:#eef1f5;color:#5b6878;border-radius:8px;padding:0 6px;}'
      + '.nav-area-num:empty{display:none;}'
      + '.nav-area-num{margin-left:auto;background:#ff3333;color:#fff;border-radius:10px;padding:0 7px;font-size:0.7rem;font-weight:700;line-height:18px;}'
      + '.area-tabs-bar{background:#fff;border-top:3px solid var(--ac,#d92020);border-bottom:1px solid #e3e7ec;box-shadow:0 1px 4px rgba(0,0,0,0.04);}'
      + '.area-punto{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:2px;box-shadow:0 0 0 2px rgba(255,255,255,0.25);}'
      + '.area-tabs-inner{display:flex;gap:2px;padding:0 20px;overflow-x:auto;scrollbar-width:thin;}'
      + '.area-tab{display:flex;align-items:center;gap:7px;padding:0 14px;min-height:46px;color:#3d4b5c;text-decoration:none;white-space:nowrap;'
      +   'font-size:0.93rem;font-weight:500;border-bottom:3px solid transparent;border-top:3px solid transparent;transition:0.12s;}'
      + '.area-tab i{font-size:1rem;color:#6c7a89;}'
      + '.area-tab:hover{color:#001f3f;background:#f4f6f8;}'
      + '.area-tab.active{color:#001f3f;font-weight:700;border-bottom-color:var(--ac,#d92020);}'
      + '.area-tab.active i{color:var(--ac,#d92020);}'
      + '.topbar-right{border-left:1px solid #23466e;}'
      + '.btn-venta{display:flex;align-items:center;gap:6px;background:#d92020;color:#fff;text-decoration:none;font-weight:700;'
      +   'border-radius:9px;padding:7px 15px;font-size:0.92rem;transition:0.15s;}'
      + '.btn-venta:hover{background:#b81a1a;color:#fff;}'
      + '.btn-redondo{width:40px;height:40px;border-radius:50%;border:1px solid #2c5280;background:transparent;color:#fff;'
      +   'display:flex;align-items:center;justify-content:center;font-size:1.05rem;cursor:pointer;}'
      + '.btn-redondo:hover{background:rgba(255,255,255,0.08);}'
      + '[data-menu="sistema"]{align-items:center;}'
      + '.notif-bell{background:transparent;color:#fff;border-color:#2c5280;}'
      + '.notif-bell:hover{background:rgba(255,255,255,0.08);}'
      + '.user-btn:hover{background:rgba(255,255,255,0.08);border-color:transparent;}'
      + '.user-avatar{background:#fff;color:#001f3f;}'
      + '.user-btn .user-name{color:#fff;}'
      + '.user-btn .user-role{background:#2c5280;}'
      + '.user-btn .chev{color:#a9bdd6;}'
      + '.topbar-burger{color:#fff;}'
      + '@media (max-width:1100px){.btn-areas span{display:none;}.btn-venta span{display:none;}}'
      + '@media (max-width:900px){'
      +   '.topbar-burger{display:block;order:0;margin-left:auto;}'
      +   '.topbar-espacio{display:none;}'
      +   '.topbar-right{border-left:none;padding-left:4px;}'
      +   '.area-tabs-bar{display:none;}'
      +   '.area-tabs-bar.abierto{display:block;}'
      +   '.area-tabs-inner{flex-direction:column;padding:6px 0;}'
      +   '.area-tab{min-height:44px;padding:0 16px;border:none;border-left:3px solid transparent;}'
      +   '.area-tab.active{border-left-color:#d92020;background:#f4f6f8;}'
      +   '.marca-bajada{display:none;}.user-btn .user-info{display:none;}}'
      + '@media (max-width:560px){[data-menu="sistema"]{display:none;}.topbar-brand .marca{display:none;}.btn-areas{padding:5px 9px;}.user-btn .chev{display:none;}}';

    var style = document.createElement('style');
    style.id = 'layout-extra-styles';
    style.textContent = css;
    document.head.appendChild(style);
  }

  /* ============ CAMPANITA: render y comportamiento ============ */

  function renderCampanita() {
    var usuario = (window.Auth && Auth.getUsuario()) ? Auth.getUsuario() : null;
    if (!usuario || !tieneRol(usuario.Rol, ROLES_NOTIFICACIONES)) return;

    if (document.getElementById('notifBellWrapper')) return;

    var wrapper = document.createElement('div');
    wrapper.id = 'notifBellWrapper';
    wrapper.className = 'notif-bell-wrapper';
    wrapper.innerHTML =
      '<div class="notif-bell" id="notifBellBtn" title="Notificaciones">' +
      '  <i class="bi bi-bell-fill"></i>' +
      '  <span class="badge-bell" id="notifBadge" style="display:none;">0</span>' +
      '</div>' +
      '<div class="notif-panel" id="notifPanel">' +
      '  <div class="head"><span><i class="bi bi-bell-fill"></i> Notificaciones</span>' +
      '    <span id="notifTotalChip" style="font-size:0.75rem;opacity:0.85;"></span>' +
      '  </div>' +
      '  <div class="body" id="notifBody">' +
      '    <div class="notif-loading">Cargando...</div>' +
      '  </div>' +
      '</div>';

    // Va DENTRO de la barra, antes del bloque de usuario.
    // Si por algun motivo no existe la barra, cae al body como antes.
    var destino = document.getElementById('topbar-right');
    if (destino) {
      var venta = destino.querySelector('.btn-venta');
      destino.insertBefore(wrapper, venta ? venta.nextSibling : destino.firstChild);
    } else {
      wrapper.style.position = 'fixed';
      wrapper.style.top = '18px';
      wrapper.style.right = '28px';
      wrapper.style.zIndex = '1050';
      document.body.appendChild(wrapper);
    }

    document.getElementById('notifBellBtn').addEventListener('click', function (e) {
      e.stopPropagation();
      cerrarMenus(null);
      var panel = document.getElementById('notifPanel');
      panel.classList.toggle('open');
      // Abrir la campanita = verlas: el numero se va y la proxima vez
      // solo aparecen las nuevas
      if (panel.classList.contains('open')) marcarVistas();
    });

    document.addEventListener('click', function (e) {
      var wrap = document.getElementById('notifBellWrapper');
      if (!wrap) return;
      if (!wrap.contains(e.target)) {
        document.getElementById('notifPanel').classList.remove('open');
      }
    });

    cargarNotificaciones();
    if (intervaloNotif) clearInterval(intervaloNotif);
    intervaloNotif = setInterval(cargarNotificaciones, POLLING_MS);
  }

  function cargarNotificaciones() {
    var url = API_BASE + 'Notificacion/Resumen';

    var token = localStorage.getItem('token');
    if (!token) return;

    fetch(url, {
      headers: { 'Authorization': 'Bearer ' + token }
    })
      .then(function (r) {
        if (!r.ok) throw new Error('http ' + r.status);
        return r.json();
      })
      .then(function (data) {
        notifUltima = data;
        var nuevas = filtrarNoVistas(data);
        actualizarBadge(contarNotif(nuevas));
        // Con el panel abierto no se cambia lo que se esta leyendo
        var panel = document.getElementById('notifPanel');
        if (!(panel && panel.classList.contains('open'))) pintarPanel();
      })
      .catch(function () {
        // Silencio: si falla, mantenemos el badge en lo ultimo conocido
      });
  }

  /* ---------- Notificaciones vistas ----------
     Se guardan en el navegador, por usuario. Cada aviso tiene una clave
     (venta anulada #12, 3 en stock critico...). Si cambia —otra venta
     anulada, 4 en stock critico— es un aviso nuevo y vuelve a aparecer. */
  var notifUltima = null, notifVerVistas = false;

  function claveVistas() {
    var u = (window.Auth && Auth.getUsuario()) ? Auth.getUsuario() : {};
    return 'notifVistas:' + (u.Id || u.IdUsuario || u.Usuario || u.Nombre || 'x');
  }
  function leerVistas() {
    try { return JSON.parse(localStorage.getItem(claveVistas()) || '[]'); } catch (e) { return []; }
  }
  function guardarVistas(lista) {
    try { localStorage.setItem(claveVistas(), JSON.stringify(lista.slice(-400))); } catch (e) { }
  }

  function clavesDe(d) {
    var k = { ventas: {}, pedidos: {}, ajustes: {} };
    (d.VentasAnuladas || []).forEach(function (v) { k.ventas['VA:' + v.Id] = v; });
    (d.PedidosCancelados || []).forEach(function (x) { k.pedidos['PC:' + x.Id] = x; });
    (d.AjustesStock || []).forEach(function (a) { k.ajustes['AJ:' + (a.Id || (a.Fecha + '|' + a.Repuesto + '|' + a.Diferencia))] = a; });
    return k;
  }

  function filtrarNoVistas(d) {
    var vistas = {}; leerVistas().forEach(function (x) { vistas[x] = 1; });
    var k = clavesDe(d), r = {};
    for (var p in d) r[p] = d[p];
    r.VentasAnuladas = Object.keys(k.ventas).filter(function (c) { return !vistas[c]; }).map(function (c) { return k.ventas[c]; });
    r.PedidosCancelados = Object.keys(k.pedidos).filter(function (c) { return !vistas[c]; }).map(function (c) { return k.pedidos[c]; });
    r.AjustesStock = Object.keys(k.ajustes).filter(function (c) { return !vistas[c]; }).map(function (c) { return k.ajustes[c]; });
    if (vistas['RS:' + d.SolicitudesReset]) r.SolicitudesReset = 0;
    if (vistas['SC:' + d.StockCritico]) r.StockCritico = 0;
    return r;
  }

  function contarNotif(d) {
    return (d.VentasAnuladas || []).length + (d.PedidosCancelados || []).length + (d.AjustesStock || []).length +
           (d.SolicitudesReset > 0 ? 1 : 0) + (d.StockCritico > 0 ? 1 : 0);
  }

  function marcarVistas() {
    if (!notifUltima) return;
    var lista = leerVistas(), k = clavesDe(notifUltima);
    [k.ventas, k.pedidos, k.ajustes].forEach(function (g) { Object.keys(g).forEach(function (c) { if (lista.indexOf(c) === -1) lista.push(c); }); });
    if (notifUltima.SolicitudesReset > 0) lista.push('RS:' + notifUltima.SolicitudesReset);
    if (notifUltima.StockCritico > 0) lista.push('SC:' + notifUltima.StockCritico);
    guardarVistas(lista);
    actualizarBadge(0);
  }

  // El panel muestra las nuevas; las ya vistas, solo si se piden
  function pintarPanel() {
    if (!notifUltima) return;
    var nuevas = filtrarNoVistas(notifUltima);
    var hayVistas = contarNotif(notifUltima) > contarNotif(nuevas);
    renderPanelContenido(notifVerVistas ? notifUltima : nuevas);
    var body = document.getElementById('notifBody');
    if (body && hayVistas) {
      var a = document.createElement('button');
      a.type = 'button';
      a.textContent = notifVerVistas ? 'Ocultar las ya vistas' : 'Ver las ya vistas';
      a.style.cssText = 'display:block;width:100%;border:none;background:none;padding:10px;font-size:0.8rem;color:#1266d1;font-weight:600;';
      a.addEventListener('click', function (e) { e.stopPropagation(); notifVerVistas = !notifVerVistas; pintarPanel(); });
      body.appendChild(a);
    }
  }

  function actualizarBadge(total) {
    var badge = document.getElementById('notifBadge');
    var chip = document.getElementById('notifTotalChip');
    if (!badge) return;

    if (total > 0) {
      badge.style.display = 'flex';
      badge.textContent = total > 9 ? '9+' : total;
      if (chip) chip.textContent = total + ' pendiente' + (total === 1 ? '' : 's');
    } else {
      badge.style.display = 'none';
      if (chip) chip.textContent = '';
    }
  }

  function fmtFechaCorta(f) {
    if (!f) return '';
    var d = new Date(f);
    var ahora = new Date();
    var diff = (ahora - d) / 1000; // segundos

    if (diff < 60) return 'hace un instante';
    if (diff < 3600) return 'hace ' + Math.floor(diff / 60) + ' min';
    if (diff < 86400) return 'hace ' + Math.floor(diff / 3600) + ' hs';
    return d.toLocaleDateString('es-AR');
  }

  function renderPanelContenido(data) {
    var body = document.getElementById('notifBody');
    if (!body) return;

    var html = '';
    var hayContenido = false;

    // Ventas anuladas
    if (data.VentasAnuladas && data.VentasAnuladas.length > 0) {
      hayContenido = true;
      html += '<div class="notif-section">';
      html += '  <div class="notif-section-title"><i class="bi bi-slash-circle"></i> Ventas anuladas (últimas 24hs)</div>';
      data.VentasAnuladas.forEach(function (v) {
        html += '<a href="ListadoVentas.html" class="notif-item">';
        html += '  <div class="icon-circle"><i class="bi bi-receipt"></i></div>';
        html += '  <div class="info">';
        html += '    <div class="title">Venta #' + v.Id + ' — ' + escape(v.Cliente) + '</div>';
        html += '    <div class="meta">Anulada por <strong>' + escape(v.AnuladoPor || '-') + '</strong> · ' + fmtFechaCorta(v.FechaAnulacion) + ' · $' + Number(v.Total).toFixed(2) + '</div>';
        html += '  </div>';
        html += '</a>';
      });
      html += '</div>';
    }

    // Pedidos cancelados
    if (data.PedidosCancelados && data.PedidosCancelados.length > 0) {
      hayContenido = true;
      html += '<div class="notif-section">';
      html += '  <div class="notif-section-title"><i class="bi bi-x-circle"></i> Pedidos cancelados</div>';
      data.PedidosCancelados.forEach(function (p) {
        html += '<a href="ListadoPedido.html" class="notif-item amarillo">';
        html += '  <div class="icon-circle"><i class="bi bi-clipboard-x"></i></div>';
        html += '  <div class="info">';
        html += '    <div class="title">Pedido #' + p.Id + ' — ' + escape(p.Proveedor) + '</div>';
        html += '    <div class="meta">Cancelado por <strong>' + escape(p.CanceladoPor || '-') + '</strong> · ' + fmtFechaCorta(p.FechaCancelacion) + '</div>';
        html += '  </div>';
        html += '</a>';
      });
      html += '</div>';
    }
    // Ajustes de stock
    if (data.AjustesStock && data.AjustesStock.length > 0) {
      hayContenido = true;
      html += '<div class="notif-section">';
      html += '  <div class="notif-section-title"><i class="bi bi-sliders"></i> Ajustes de stock (últimas 24hs)</div>';
      data.AjustesStock.forEach(function (a) {
        var dif = a.Diferencia;
        var difTxt = dif > 0 ? '+' + dif : '' + dif;
        var cod = a.CodigoRepuesto ? '[' + escape(a.CodigoRepuesto) + '] ' : '';
        html += '<a href="AjusteStock.html" class="notif-item verde">';
        html += '  <div class="icon-circle"><i class="bi bi-sliders"></i></div>';
        html += '  <div class="info">';
        html += '    <div class="title">' + cod + escape(a.Repuesto) + ' (' + difTxt + ')</div>';
        html += '    <div class="meta">' + escape(a.Tipo) + ' por <strong>' + escape(a.AjustadoPor || '-') + '</strong> · ' + fmtFechaCorta(a.Fecha) + '</div>';
        html += '  </div>';
        html += '</a>';
      });
      html += '</div>';
    }
    // Solicitudes de reset
    if (data.SolicitudesReset && data.SolicitudesReset > 0) {
      hayContenido = true;
      html += '<div class="notif-section">';
      html += '  <div class="notif-section-title"><i class="bi bi-key"></i> Solicitudes pendientes</div>';
      html += '<a href="UsuariosListado.html" class="notif-item azul">';
      html += '  <div class="icon-circle"><i class="bi bi-person-lock"></i></div>';
      html += '  <div class="info">';
      html += '    <div class="title">' + data.SolicitudesReset + ' usuario(s) pidieron resetear su clave</div>';
      html += '    <div class="meta">Click para ver y procesarlas</div>';
      html += '  </div>';
      html += '</a>';
      html += '</div>';
    }

    // Stock crítico
    if (data.StockCritico && data.StockCritico > 0) {
      hayContenido = true;
      html += '<div class="notif-section">';
      html += '  <div class="notif-section-title"><i class="bi bi-exclamation-triangle"></i> Inventario</div>';
      html += '<a href="StockRepuestos.html" class="notif-item amarillo">';
      html += '  <div class="icon-circle"><i class="bi bi-box-seam"></i></div>';
      html += '  <div class="info">';
      html += '    <div class="title">' + data.StockCritico + ' repuesto(s) en stock crítico</div>';
      html += '    <div class="meta">Click para ver el listado</div>';
      html += '  </div>';
      html += '</a>';
      html += '</div>';
    }

    if (!hayContenido) {
      html = '<div class="notif-empty">' +
        '<i class="bi bi-bell-slash"></i>' +
        '<div>No hay notificaciones nuevas.</div>' +
        '<small class="text-muted">Las que ya viste no se vuelven a mostrar.</small>' +
        '</div>';
    }

    body.innerHTML = html;
  }

  /* ============ INDICADORES DEL MENU ============ */

  var API_INDICADORES = API_BASE + 'Indicador';

  /* Lo que reclama atencion se marca con un numero: en la opcion del
     area (si esta en pantalla) y en el desplegable para cambiar de area.
     El inicio queda limpio a proposito.

     Si la consulta falla, no se muestra nada: un indicador es
     informacion adicional, no puede romper la navegacion. */
  function cargarIndicadores() {
    if (!window.fetchAuth) return;

    fetchAuth(API_INDICADORES)
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (datos) {
        if (!datos || !datos[0]) return;
        var d = datos[0];

        // Compras: lo que falta reponer, lo que quedo en el carrito y los pedidos en armado
        var enArmado = d.PedidosEnArmado || 0;
        var compras = (d.Reposicion || 0) + (d.EnCarrito || 0) + enArmado;
        pintarArea('compras', compras,
                   (d.Reposicion || 0) + ' para reponer · ' + (d.EnCarrito || 0) + ' en el carrito · ' + enArmado + ' pedido(s) en armado');
        pintarItem('ListadoPedido.html', enArmado, enArmado + ' pedido(s) en armado: cargalos en la web del proveedor');
        pintarItem('Carrito.html', d.EnCarrito || 0, (d.EnCarrito || 0) + ' repuesto(s) en el carrito sin confirmar');
        pintarItem('PedidoNuevo.html', d.Reposicion || 0, (d.Reposicion || 0) + ' repuesto(s) para reponer');

        // Ventas: los encargos que piden accion
        var avisar = d.EncargosParaAvisar || 0, atrasados = d.EncargosAtrasados || 0, noRetiro = d.EncargosNoRetiro || 0;
        var encargos = avisar + atrasados + noRetiro;
        var txtEnc = [];
        if (avisar) txtEnc.push(avisar + ' para avisar');
        if (atrasados) txtEnc.push(atrasados + ' atrasado(s)');
        if (noRetiro) txtEnc.push(noRetiro + ' sin retirar');
        pintarArea('ventas', encargos, 'Encargos: ' + txtEnc.join(', '));
        pintarItem('Encargos.html', encargos, 'Encargos: ' + txtEnc.join(', '));

        // Administracion: clientes con deuda (informacion, no urgencia)
        pintarItem('CuentaCorriente.html', d.ClientesConDeuda || 0, (d.ClientesConDeuda || 0) + ' cliente(s) con saldo pendiente', true);
      })
      .catch(function () { /* sin indicadores */ });
  }

  // Numero chico al lado de una opcion (pestaña del area o menu)
  function pintarItem(href, cantidad, titulo, suave) {
    document.querySelectorAll('a.topnav-menu-item[href="' + href + '"], a.area-tab[href="' + href + '"], a.area-card[href="' + href + '"]').forEach(function (a) {
      var viejo = a.querySelector('.nav-item-num');
      if (viejo) viejo.remove();
      if (!cantidad || cantidad <= 0) return;
      var n = document.createElement('span');
      n.className = 'nav-item-num';
      n.textContent = cantidad > 99 ? '99+' : cantidad;
      n.title = titulo || '';
      n.style.cssText = 'margin-left:6px;background:' + (suave ? '#c47700' : '#ff3333') + ';color:#fff;border-radius:10px;padding:0 7px;font-size:0.7rem;font-weight:700;line-height:18px;' +
        (a.classList.contains('area-card') ? 'align-self:flex-start;margin:auto 0 0;' : '');
      a.appendChild(n);
    });
  }

  // Numero en el desplegable de areas
  function pintarArea(clave, cantidad, titulo) {
    document.querySelectorAll('[data-area-globo="' + clave + '"]').forEach(function (el) {
      el.textContent = cantidad > 0 ? (cantidad > 99 ? '99+' : String(cantidad)) : '';
      el.title = cantidad > 0 ? (titulo || '') : '';
    });
  }

  /* ============ ESTADISTICAS PLEGABLES ============ */
  // Sirve en cualquier listado que tenga:
  //   <button id="btnStats">  y  <div id="statsWrap">
  // Recuerda si quedaron abiertas o cerradas entre pantallas.
  var CLAVE_STATS = 'daytona_stats_abiertas';

  function initEstadisticas() {
    var wrap = document.getElementById('statsWrap');
    var btn = document.getElementById('btnStats');
    if (!wrap || !btn) return;

    var abierto = localStorage.getItem(CLAVE_STATS) === '1';

    function pintar(v) {
      if (v) wrap.classList.add('abierto');
      else wrap.classList.remove('abierto');
      var txt = btn.querySelector('.txt');
      var chev = btn.querySelector('.chev');
      if (txt) txt.textContent = v ? 'Ocultar estadísticas' : 'Ver estadísticas';
      if (chev) chev.className = 'bi chev ' + (v ? 'bi-chevron-up' : 'bi-chevron-down');
    }

    pintar(abierto);

    btn.addEventListener('click', function () {
      abierto = !abierto;
      localStorage.setItem(CLAVE_STATS, abierto ? '1' : '0');
      pintar(abierto);
    });
  }

  /* ============ INICIO ============ */

  window.addEventListener('DOMContentLoaded', function () {
    if (window.Auth && !Auth.getToken()) return;
    inyectarEstilos();
    var activeKey = document.body.getAttribute('data-page') || '';
    renderTopbar(activeKey);
    engancharCierres();
    renderCampanita();
    initEstadisticas();
    cargarIndicadores();
  });

  window.Layout = {
    renderTopbar: renderTopbar,
    renderSidebar: renderTopbar,   // alias: por si alguna pagina lo llamaba con el nombre viejo
    toggleMenu: toggleMenu,
    toggleBurger: toggleBurger,
    initEstadisticas: initEstadisticas,
    refrescarIndicadores: cargarIndicadores,
    tieneRol: tieneRol,
    refrescarNotificaciones: cargarNotificaciones,
    // Para el inicio y la pantalla de cada area
    areas: function () { return AREAS; },
    area: buscarArea,
    areasVisibles: areasVisibles,
    itemsVisibles: itemsVisibles
  };
})();
