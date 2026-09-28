(function () {
  'use strict';

  // ==========================================================
  // NAV — cada SECCION es un item de la barra de arriba.
  // Si la seccion tiene una sola pagina, se muestra como link directo.
  // Si tiene varias, se muestra como desplegable.
  // Para mover algo de lugar, basta con cambiarlo de seccion aca.
  // ==========================================================
  var NAV = [
    {
      section: 'Dashboard',
      icon: 'bi-speedometer2',
      items: [
        { key: 'dashboard', label: 'Dashboard', icon: 'bi-speedometer2', href: 'Dashboard.html',
          roles: ['Dueño', 'Administrador', 'Supervisor'] }
      ]
    },
    {
      section: 'Catálogo',
      icon: 'bi-journal-bookmark',
      items: [
        { key: 'buscador', label: 'Buscador', icon: 'bi-search', href: 'Buscador.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor', 'Analista'] },
        { key: 'repuestos-stock', label: 'Stock', icon: 'bi-box-seam', href: 'StockRepuestos.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor', 'Analista'] },
        { key: 'ajuste-stock', label: 'Ajuste de Stock', icon: 'bi-sliders', href: 'AjusteStock.html',
          roles: ['Administrador', 'Analista', 'Vendedor'] },
        { key: 'marcas', label: 'Marcas', icon: 'bi-tag', href: 'MarcasListado.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'modelos', label: 'Modelos', icon: 'bi-car-front', href: 'ModelosListado.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] },
        { key: 'rubros', label: 'Rubros', icon: 'bi-folder2-open', href: 'RubrosListado.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] }
      ]
    },
    {
      section: 'Ventas',
      icon: 'bi-cart3',
      items: [
        { key: 'venta-nueva', label: 'Venta', icon: 'bi-cart-plus', href: 'CargarVenta.html',
          roles: ['Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'ventas', label: 'Listado de Ventas', icon: 'bi-receipt', href: 'ListadoVentas.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'presupuestos', label: 'Presupuestos', icon: 'bi-file-earmark-text', href: 'ListadoPresupuestos.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'cuentacorriente', label: 'Cuenta Corriente', icon: 'bi-journal-text', href: 'CuentaCorriente.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'clientes', label: 'Clientes', icon: 'bi-people', href: 'ClientesListado.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] }
      ]
    },
    {
      section: 'Compras',
      icon: 'bi-truck',
      items: [
        { key: 'pedido-nuevo', label: 'Pedido', icon: 'bi-box-seam', href: 'PedidoNuevo.html',
          roles: ['Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'pedidos', label: 'Listado de Pedidos', icon: 'bi-clipboard-data', href: 'ListadoPedido.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'proveedores', label: 'Proveedores', icon: 'bi-shop', href: 'ProveedoresListado.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor'] },
        { key: 'catalogo-prov', label: 'Catálogo de Proveedores', icon: 'bi-search', href: 'CatalogoProveedores.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Analista'] }
      ]
    },
    {
      section: 'Caja',
      icon: 'bi-cash-stack',
      items: [
        { key: 'caja', label: 'Caja', icon: 'bi-cash-stack', href: 'Caja.html',
          roles: ['Dueño', 'Administrador', 'Vendedor'] }
      ]
    },
    {
      section: 'Reportes',
      icon: 'bi-graph-up',
      items: [
        { key: 'rep-stock', label: 'Stock Crítico', icon: 'bi-exclamation-triangle', href: 'ReporteStockCritico.html',
          roles: ['Dueño', 'Administrador', 'Supervisor', 'Vendedor', 'Analista'] },
        { key: 'rep-ventas', label: 'Ventas por Período', icon: 'bi-graph-up', href: 'ReporteVentas.html',
          roles: ['Dueño', 'Administrador', 'Supervisor'] },
        { key: 'rep-caja', label: 'Resumen de Caja', icon: 'bi-cash-coin', href: 'ReporteCaja.html',
          roles: ['Dueño', 'Administrador'] }
      ]
    },
    {
      // Configuracion + Administracion fusionadas: los 4 son solo Administrador
      section: 'Sistema',
      icon: 'bi-gear',
      items: [
        { key: 'configuracion', label: 'Beneficios y parámetros', icon: 'bi-percent', href: 'Configuracion.html',
          roles: ['Dueño', 'Administrador'] },
        { key: 'usuarios', label: 'Usuarios', icon: 'bi-people-fill', href: 'UsuariosListado.html',
          roles: ['Administrador'] },
        { key: 'roles', label: 'Roles', icon: 'bi-shield-lock-fill', href: 'RolesListado.html',
          roles: ['Administrador'] },
        { key: 'estados-venta', label: 'Estados de Venta', icon: 'bi-tags', href: 'EstadosVentaListado.html',
          roles: ['Administrador'] },
        { key: 'estados-pedido', label: 'Estados de Pedido', icon: 'bi-tags-fill', href: 'EstadosPedidoListado.html',
          roles: ['Administrador'] }
      ]
    }
  ];

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

  /* ============ RENDER DE LA BARRA SUPERIOR ============ */

  function renderSeccion(group, activeKey, rolUsuario) {
    var visibles = itemsVisibles(group, rolUsuario);
    if (visibles.length === 0) return '';

    var activa = visibles.some(function (it) { return it.key === activeKey; });
    var clsActiva = activa ? ' active' : '';

    // Una sola pagina: link directo, sin desplegable
    if (visibles.length === 1) {
      var solo = visibles[0];
      return '<a href="' + solo.href + '" class="topnav-link' + clsActiva + '">' +
        '<i class="bi ' + (group.icon || solo.icon) + ' ico"></i>' +
        '<span class="lbl">' + escape(group.section) + '</span>' +
        '</a>';
    }

    // Varias paginas: desplegable
    var html = '<div class="topnav-item" data-menu="' + group.key + '">';
    html += '<button type="button" class="topnav-link' + clsActiva + '" ' +
      'onclick="Layout.toggleMenu(\'' + group.key + '\')">';
    html += '<i class="bi ' + group.icon + ' ico"></i>';
    html += '<span class="lbl">' + escape(group.section) +
      '<i class="bi bi-chevron-down chev"></i></span>';
    html += '</button>';

    html += '<div class="topnav-menu">';
    visibles.forEach(function (it) {
      var cls = it.key === activeKey ? ' active' : '';
      html += '<a href="' + it.href + '" class="topnav-menu-item' + cls + '">' +
        '<i class="bi ' + it.icon + '"></i> ' + escape(it.label) + '</a>';
    });
    html += '</div></div>';
    return html;
  }

  function renderTopbar(activeKey) {
    var container = document.getElementById('sidebar-container');
    if (!container) return;

    var usuario = (window.Auth && Auth.getUsuario()) ? Auth.getUsuario() : null;
    var rolUsuario = usuario ? usuario.Rol : null;

    // clave estable por seccion, para el toggle del desplegable
    NAV.forEach(function (g, idx) {
      if (!g.key) g.key = 'sec' + idx;
    });

    var html = '<header class="topbar"><div class="topbar-inner">';

    html += '<a class="topbar-brand" href="Dashboard.html">' +
      '<i class="bi bi-flag-fill"></i>' +
      '<span class="marca">' +
        '<span class="marca-nombre">DAYTONA</span>' +
        '<span class="marca-bajada">REPUESTOS AUTOMOTOR</span>' +
      '</span></a>';

    html += '<button type="button" class="topbar-burger" onclick="Layout.toggleBurger()" ' +
      'aria-label="Menú"><i class="bi bi-list"></i></button>';

    html += '<nav class="topnav" id="topnav">';
    NAV.forEach(function (group) {
      html += renderSeccion(group, activeKey, rolUsuario);
    });
    html += '</nav>';

    html += '<div class="topbar-right" id="topbar-right">';
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

    html += '</div></header>';
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
      + '.marca{display:flex;flex-direction:column;line-height:1;}'
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
      + '@media (max-width:1400px){.topnav-link{padding:9px 13px 7px;}.topnav-link .lbl{font-size:0.9rem;}'
      +   '.topnav-link .ico{font-size:1.3rem;}}'
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
      +   '.notif-panel{width:calc(100vw - 28px);right:-8px;}}';

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
      destino.insertBefore(wrapper, destino.firstChild);
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
      document.getElementById('notifPanel').classList.toggle('open');
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
        actualizarBadge(data.Total || 0);
        renderPanelContenido(data);
      })
      .catch(function () {
        // Silencio: si falla, mantenemos el badge en lo ultimo conocido
      });
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
        '<div>No hay notificaciones pendientes.</div>' +
        '<small class="text-muted">Todo en orden por aquí.</small>' +
        '</div>';
    }

    body.innerHTML = html;
  }

  /* ============ INDICADORES DEL MENU ============ */

  var API_INDICADORES = API_BASE + 'Indicador';

  /* Un globo sobre el icono de la seccion, con la cantidad de cosas
     que reclaman atencion. La idea es que el usuario vea que hay algo
     pendiente sin tener que entrar a buscarlo.

     Si la consulta falla, no se muestra nada: un indicador es
     informacion adicional, no puede romper la navegacion. */
  function cargarIndicadores() {
    if (!window.fetchAuth) return;

    fetchAuth(API_INDICADORES)
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (datos) {
        if (!datos || !datos[0]) return;
        var d = datos[0];

        // Compras: repuestos bajo el minimo
        pintarGlobo('sec3', d.Reposicion, false,
                    d.Reposicion + ' repuesto(s) para reponer' +
                    (d.SinStock > 0 ? ', ' + d.SinStock + ' sin stock' : ''));

        // Ventas: clientes con deuda. En naranja, no en rojo: deber no
        // es una urgencia, es informacion.
        pintarGlobo('sec2', d.ClientesConDeuda, true,
                    d.ClientesConDeuda + ' cliente(s) con saldo pendiente');
      })
      .catch(function () { /* sin indicadores */ });
  }

  function pintarGlobo(claveSeccion, cantidad, suave, titulo) {
    var item = document.querySelector('.topnav-item[data-menu="' + claveSeccion + '"]');
    if (!item) return;

    var link = item.querySelector('.topnav-link');
    if (!link) return;

    var viejo = link.querySelector('.nav-globo');
    if (viejo) viejo.remove();

    if (!cantidad || cantidad <= 0) return;

    var globo = document.createElement('span');
    globo.className = 'nav-globo' + (suave ? ' suave' : '');
    globo.textContent = cantidad > 99 ? '99+' : cantidad;
    globo.title = titulo || '';
    link.appendChild(globo);
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
    refrescarNotificaciones: cargarNotificaciones
  };
})();
