// Catálogo ficticio de Mercado Norte. Datos sintéticos; no hay precios ni inventario reales.
const CATALOG = [
  { id: "botella-andina", name: "Botella térmica Andina", category: "Hogar", price: 24.0, stock: 42, tone: "t1",
    summary: "Acero inoxidable · 750 ml", description: "Mantiene bebidas frías 24 horas o calientes 12 horas. Tapa de rosca con cierre hermético." },
  { id: "mochila-sendero-24", name: "Mochila Sendero 24L", category: "Outdoor", price: 68.0, stock: 15, tone: "t2",
    summary: "Material reciclado · resistente al agua", description: "Compartimento para laptop de 15\", bolsillo lateral para botella y espalda ventilada." },
  { id: "lampara-nomada", name: "Lámpara Nómada", category: "Hogar", price: 39.0, stock: 27, tone: "t3",
    summary: "LED recargable · luz cálida", description: "Hasta 20 horas de autonomía con tres niveles de brillo. Base magnética." },
  { id: "cafetera-prensa-francesa", name: "Cafetera de prensa francesa", category: "Cocina", price: 31.5, stock: 60, tone: "t4",
    summary: "Vidrio borosilicato · 1 L", description: "Filtro de malla fina y mango de madera. Apta para lavavajillas en la parte superior." },
  { id: "cuaderno-tapa-dura", name: "Cuaderno de tapa dura A5", category: "Oficina", price: 12.9, stock: 110, tone: "t5",
    summary: "192 páginas · papel 90 g", description: "Hojas punteadas, cinta marcapáginas y bolsillo interior." },
  { id: "tienda-campana-2p", name: "Tienda de campaña 2 personas", category: "Outdoor", price: 129.0, stock: 8, tone: "t6",
    summary: "Impermeable 3000 mm · 1,9 kg", description: "Armado en menos de cinco minutos. Incluye mosquitero y piquetas de aluminio." },
  { id: "organizador-cables", name: "Organizador de cables", category: "Oficina", price: 8.5, stock: 200, tone: "t1",
    summary: "Set de 6 piezas · silicona", description: "Sujeta y ordena cables de escritorio. Se adhiere a superficies lisas." },
  { id: "tabla-madera-acacia", name: "Tabla de cortar de acacia", category: "Cocina", price: 27.0, stock: 33, tone: "t2",
    summary: "Madera maciza · 35 x 25 cm", description: "Canaleta para jugos y asas laterales. Aceite de mantenimiento incluido." },
  { id: "manta-tejida", name: "Manta tejida Altiplano", category: "Hogar", price: 45.0, stock: 19, tone: "t3",
    summary: "Algodón orgánico · 140 x 180 cm", description: "Tejido denso, lavable a máquina en ciclo suave." },
  { id: "termo-viaje-500", name: "Termo de viaje 500 ml", category: "Outdoor", price: 18.75, stock: 75, tone: "t4",
    summary: "Doble pared · tapa con sorbo", description: "Cabe en portavasos estándar y mantiene la temperatura durante la mañana." },
  { id: "silla-plegable-ligera", name: "Silla plegable ligera", category: "Outdoor", price: 54.0, stock: 12, tone: "t5",
    summary: "Carga máxima 120 kg · 2,4 kg", description: "Estructura de aluminio, bolsa de transporte y respaldo acolchado." },
  { id: "pizarra-escritorio", name: "Pizarra magnética de escritorio", category: "Oficina", price: 22.4, stock: 46, tone: "t6",
    summary: "40 x 30 cm · incluye marcadores", description: "Superficie borrable con soporte inclinable y dos imanes." },
  { id: "molinillo-manual", name: "Molinillo manual de cerámica", category: "Cocina", price: 36.9, stock: 22, tone: "t1",
    summary: "Muela cerámica · ajuste de 12 niveles", description: "Cuerpo de madera de haya y cajón extraíble para la molienda." }
];

const SHIPPING_FLAT = 5.9;
const FREE_SHIPPING_FROM = 50;
const TAX_RATE = 0.13;
