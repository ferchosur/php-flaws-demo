// Fictional Worst Market catalog. Synthetic data; no real prices or inventory.
const CATALOG = [
  { id: "botella-andina", name: "Andina Thermal Bottle", category: "Home", price: 24.0, stock: 42, tone: "t1",
    summary: "Stainless steel · 750 ml", description: "Keeps drinks cold for 24 hours or hot for 12 hours. Screw cap with airtight seal." },
  { id: "mochila-sendero-24", name: "Sendero 24L Backpack", category: "Outdoor", price: 68.0, stock: 15, tone: "t2",
    summary: "Recycled material · water resistant", description: "15\" laptop compartment, side bottle pocket and ventilated back." },
  { id: "lampara-nomada", name: "Nomad Lamp", category: "Home", price: 39.0, stock: 27, tone: "t3",
    summary: "Rechargeable LED · warm light", description: "Up to 20 hours of runtime with three brightness levels. Magnetic base." },
  { id: "cafetera-prensa-francesa", name: "French Press Coffee Maker", category: "Kitchen", price: 31.5, stock: 60, tone: "t4",
    summary: "Borosilicate glass · 1 L", description: "Fine mesh filter and wooden handle. Top-rack dishwasher safe." },
  { id: "cuaderno-tapa-dura", name: "A5 Hardcover Notebook", category: "Office", price: 12.9, stock: 110, tone: "t5",
    summary: "192 pages · 90 g paper", description: "Dotted pages, bookmark ribbon and inner pocket." },
  { id: "tienda-campana-2p", name: "2-Person Tent", category: "Outdoor", price: 129.0, stock: 8, tone: "t6",
    summary: "Waterproof 3000 mm · 1.9 kg", description: "Pitched in under five minutes. Includes mosquito net and aluminum stakes." },
  { id: "organizador-cables", name: "Cable Organizer", category: "Office", price: 8.5, stock: 200, tone: "t1",
    summary: "Set of 6 pieces · silicone", description: "Holds and tidies desk cables. Sticks to smooth surfaces." },
  { id: "tabla-madera-acacia", name: "Acacia Cutting Board", category: "Kitchen", price: 27.0, stock: 33, tone: "t2",
    summary: "Solid wood · 35 x 25 cm", description: "Juice groove and side handles. Maintenance oil included." },
  { id: "manta-tejida", name: "Altiplano Woven Blanket", category: "Home", price: 45.0, stock: 19, tone: "t3",
    summary: "Organic cotton · 140 x 180 cm", description: "Dense weave, machine washable on a gentle cycle." },
  { id: "termo-viaje-500", name: "500 ml Travel Mug", category: "Outdoor", price: 18.75, stock: 75, tone: "t4",
    summary: "Double wall · sip lid", description: "Fits standard cup holders and keeps its temperature through the morning." },
  { id: "silla-plegable-ligera", name: "Lightweight Folding Chair", category: "Outdoor", price: 54.0, stock: 12, tone: "t5",
    summary: "Max load 120 kg · 2.4 kg", description: "Aluminum frame, carry bag and padded backrest." },
  { id: "pizarra-escritorio", name: "Magnetic Desk Whiteboard", category: "Office", price: 22.4, stock: 46, tone: "t6",
    summary: "40 x 30 cm · includes markers", description: "Erasable surface with a tilting stand and two magnets." },
  { id: "molinillo-manual", name: "Manual Ceramic Grinder", category: "Kitchen", price: 36.9, stock: 22, tone: "t1",
    summary: "Ceramic burr · 12-level adjustment", description: "Beechwood body and removable drawer for the grounds." }
];

const SHIPPING_FLAT = 5.9;
const FREE_SHIPPING_FROM = 50;
const TAX_RATE = 0.13;
