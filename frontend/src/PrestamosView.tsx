import { useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import "./PrestamosView.css";
import "./Reenganche.css";

const API = import.meta.env.VITE_API_URL ?? "http://localhost:5159";
type Cliente = { id: number; nombre: string };
type Prestamo = {
  id: number;
  cliente: string;
  tipo: string;
  frecuencia: string;
  estado: string;
  montoPrestado: number;
  cuota?: number;
  periodos?: number;
  totalPagar?: number;
  redito?: number;
  fechaInicio: string;
  saldoPendiente: number;
  prestamoOrigenId?: number;
  montoDescontado?: number;
  montoEntregado?: number;
};
type Cuota = {
  id: number;
  numero: number;
  vencimiento: string;
  programado: number;
  pagado: number;
  estado: string;
};
type Elegible = {
  id: number;
  clienteId: number;
  cliente: string;
  montoOriginal: number;
  saldoPendiente: number;
  cuotasPagadas: number;
  totalCuotas: number;
};
const money = (v = 0) =>
  new Intl.NumberFormat("es-DO", { style: "currency", currency: "DOP" }).format(
    v,
  );
async function request(path: string, token: string, options: RequestInit = {}) {
  const r = await fetch(`${API}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...options.headers,
    },
  });
  if (!r.ok)
    throw new Error(
      (await r.json().catch(() => ({}))).message ??
        "No fue posible completar la solicitud.",
    );
  return r.status === 204 ? null : r.json();
}

export default function PrestamosView({
  token,
  clientes,
  onChanged,
}: {
  token: string;
  clientes: Cliente[];
  onChanged: () => void;
}) {
  const [items, setItems] = useState<Prestamo[]>([]),
    [buscar, setBuscar] = useState(""),
    [tipo, setTipo] = useState(""),
    [estado, setEstado] = useState("");
  const [modal, setModal] = useState(false),
    [tipoNuevo, setTipoNuevo] = useState<"SAN" | "REDITO" | "REENGANCHE">(
      "SAN",
    ),
    [detalle, setDetalle] = useState<{
      prestamo: Prestamo;
      cuotas: Cuota[];
    } | null>(null),
    [error, setError] = useState(""),
    [saving, setSaving] = useState(false);
  const [elegibles, setElegibles] = useState<Elegible[]>([]),
    [origenId, setOrigenId] = useState(0),
    [montoNuevo, setMontoNuevo] = useState(0);
  const [frecuenciaNueva, setFrecuenciaNueva] = useState("SEMANAL"),
    [cuotaNueva, setCuotaNueva] = useState(0),
    [periodosNuevos, setPeriodosNuevos] = useState(13);
  const cargar = () =>
    request("/api/prestamos", token)
      .then(setItems)
      .catch((e) => setError(e.message));
  useEffect(() => {
    void cargar();
  }, [token]);
  useEffect(() => {
    if (modal)
      request("/api/prestamos/reenganches/elegibles", token)
        .then(setElegibles)
        .catch((e) => setError(e.message));
  }, [modal, token]);
  const visibles = useMemo(
    () =>
      items.filter(
        (p) =>
          (!buscar ||
            (p.cliente + " " + p.id)
              .toLowerCase()
              .includes(buscar.toLowerCase())) &&
          (!tipo || p.tipo === tipo) &&
          (!estado || p.estado === estado),
      ),
    [items, buscar, tipo, estado],
  );
  const activos = items.filter((p) => p.estado === "ACTIVO").length,
    pendiente = items.reduce((a, p) => a + p.saldoPendiente, 0);
  function abrirNuevo() {
    setTipoNuevo("SAN");
    setFrecuenciaNueva("SEMANAL");
    setCuotaNueva(0);
    setPeriodosNuevos(13);
    setOrigenId(0);
    setMontoNuevo(0);
    setModal(true);
  }
  async function crear(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setSaving(true);
    setError("");
    const f = new FormData(e.currentTarget);
    const renewal = tipoNuevo === "REENGANCHE";
    const body = renewal
      ? {
          prestamoOrigenId: Number(f.get("prestamoOrigenId")),
          montoNuevo: Number(f.get("montoPrestado")),
          cuota: Number(f.get("cuota")),
          periodos: Number(f.get("periodos")),
          frecuencia: f.get("frecuencia"),
          fechaInicio: f.get("fechaInicio"),
          observacion: f.get("observacion"),
        }
      : {
          clienteId: Number(f.get("clienteId")),
          tipo: tipoNuevo,
          montoPrestado: Number(f.get("montoPrestado")),
          frecuencia: f.get("frecuencia"),
          fechaInicio: f.get("fechaInicio"),
          cuota: tipoNuevo === "SAN" ? Number(f.get("cuota")) : null,
          periodos: tipoNuevo === "SAN" ? Number(f.get("periodos")) : null,
          redito: tipoNuevo === "REDITO" ? Number(f.get("redito")) : null,
          observacion: f.get("observacion"),
        };
    try {
      await request(
        renewal ? "/api/prestamos/reenganches" : "/api/prestamos",
        token,
        { method: "POST", body: JSON.stringify(body) },
      );
      setModal(false);
      setOrigenId(0);
      setMontoNuevo(0);
      setCuotaNueva(0);
      setPeriodosNuevos(13);
      await cargar();
      onChanged();
    } catch (x) {
      setError((x as Error).message);
    } finally {
      setSaving(false);
    }
  }
  async function abrir(id: number) {
    try {
      setDetalle(await request(`/api/prestamos/${id}`, token));
    } catch (x) {
      setError((x as Error).message);
    }
  }
  return (
    <section className="loans-page">
      {error && (
        <div className="inline-error">
          {error}
          <button onClick={() => setError("")}>×</button>
        </div>
      )}
      <div className="loan-overview">
        <div>
          <span>Préstamos activos</span>
          <strong>{activos}</strong>
        </div>
        <div>
          <span>Saldo pendiente</span>
          <strong>{money(pendiente)}</strong>
        </div>
        <div>
          <span>Total en cartera</span>
          <strong>{items.length}</strong>
        </div>
        <button onClick={abrirNuevo}>＋ Nuevo préstamo</button>
      </div>
      <section className="loan-list">
        <div className="loan-filters">
          <label className="search">
            <span>⌕</span>
            <input
              value={buscar}
              onChange={(e) => setBuscar(e.target.value)}
              placeholder="Buscar cliente o préstamo"
              autoComplete="off"
            />
          </label>
          <div className="filter-group">
            <select
              value={tipo}
              onChange={(e) => setTipo(e.target.value)}
              autoComplete="off"
            >
              <option value="">Todos los tipos</option>
              <option value="SAN">SAN</option>
              <option value="REDITO">Rédito</option>
            </select>
            <select
              value={estado}
              onChange={(e) => setEstado(e.target.value)}
              autoComplete="off"
            >
              <option value="">Todos los estados</option>
              <option value="ACTIVO">ACTIVO</option>
              <option value="SALDADO">SALDADO</option>
              <option value="ATRASADO">ATRASADO</option>
              <option value="CANCELADO">CANCELADO</option>
            </select>
          </div>
        </div>
        <div className="table-wrap">
          <table className="loans-table">
            <thead>
              <tr>
                <th>Préstamo</th>
                <th>Tipo</th>
                <th>Monto</th>
                <th>Saldo</th>
                <th>Frecuencia</th>
                <th>Estado</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visibles.map((p) => (
                <tr key={p.id}>
                  <td>
                    <div className="loan-client">
                      <b>{p.cliente}</b>
                      <small>
                        PR-{String(p.id).padStart(5, "0")} ·{" "}
                        {new Date(
                          p.fechaInicio + "T00:00:00",
                        ).toLocaleDateString("es-DO")}
                      </small>
                    </div>
                  </td>
                  <td>
                    <span
                      className={`type-badge ${p.tipo === "SAN" ? "san" : "redito"}`}
                    >
                      {p.tipo === "REDITO" ? "RÉDITO" : p.tipo}
                    </span>
                  </td>
                  <td>{money(p.montoPrestado)}</td>
                  <td>
                    <b>{money(p.saldoPendiente)}</b>
                  </td>
                  <td className="muted">{p.frecuencia}</td>
                  <td>
                    <span className={`loan-status ${p.estado.toLowerCase()}`}>
                      {p.estado}
                    </span>
                  </td>
                  <td>
                    <button className="row-action" onClick={() => abrir(p.id)}>
                      Ver →
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {visibles.length === 0 && (
            <div className="empty-loans">
              <b>No hay préstamos que coincidan</b>
              <span>Pruebe cambiando los filtros o registre uno nuevo.</span>
            </div>
          )}
        </div>
      </section>
      {modal && (
        <div className="modal-backdrop" onMouseDown={() => setModal(false)}>
          <form
            className="loan-modal"
            onSubmit={crear}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="modal-head">
              <div>
                <span>Nuevo préstamo</span>
                <h2>
                  {tipoNuevo === "REENGANCHE"
                    ? "Renovar préstamo SAN"
                    : "Condiciones del préstamo"}
                </h2>
              </div>
              <button
                type="button"
                className="close-button"
                onClick={() => setModal(false)}
              >
                ×
              </button>
            </div>
            <div className="loan-type-switch three">
              <button
                type="button"
                className={tipoNuevo === "SAN" ? "selected" : ""}
                onClick={() => setTipoNuevo("SAN")}
              >
                <b>SAN</b>
                <span>Cuotas fijas</span>
              </button>
              <button
                type="button"
                className={tipoNuevo === "REDITO" ? "selected" : ""}
                onClick={() => setTipoNuevo("REDITO")}
              >
                <b>Rédito</b>
                <span>Interés periódico</span>
              </button>
              <button
                type="button"
                className={tipoNuevo === "REENGANCHE" ? "selected" : ""}
                onClick={() => setTipoNuevo("REENGANCHE")}
              >
                <b>Reenganche</b>
                <span>Renovación SAN</span>
              </button>
            </div>
            <div className="loan-form-grid">
              {tipoNuevo === "REENGANCHE" ? (
                <>
                  <label className="full">
                    Préstamo SAN de origen
                    <select
                      name="prestamoOrigenId"
                      required
                      value={origenId || ""}
                      onChange={(e) => setOrigenId(Number(e.target.value))}
                    >
                      <option value="" disabled>
                        Seleccione el préstamo que se renovará
                      </option>
                      {elegibles.map((p) => (
                        <option value={p.id} key={p.id}>
                          {p.cliente} · PR-{String(p.id).padStart(5, "0")} ·
                          Saldo {money(p.saldoPendiente)}
                        </option>
                      ))}
                    </select>
                  </label>
                  {origenId > 0 && (
                    <div className="renewal-summary full">
                      {(() => {
                        const p = elegibles.find((x) => x.id === origenId)!;
                        return (
                          <>
                            <div>
                              <span>Saldo a descontar</span>
                              <b>{money(p.saldoPendiente)}</b>
                            </div>
                            <div>
                              <span>Cuotas pagadas</span>
                              <b>
                                {p.cuotasPagadas} de {p.totalCuotas}
                              </b>
                            </div>
                            <div>
                              <span>Efectivo a entregar</span>
                              <b>
                                {money(
                                  Math.max(0, montoNuevo - p.saldoPendiente),
                                )}
                              </b>
                            </div>
                          </>
                        );
                      })()}
                    </div>
                  )}
                </>
              ) : (
                <label className="full">
                  Cliente
                  <select name="clienteId" required defaultValue="">
                    <option value="" disabled>
                      Seleccione un cliente
                    </option>
                    {clientes.map((c) => (
                      <option value={c.id} key={c.id}>
                        {c.nombre}
                      </option>
                    ))}
                  </select>
                </label>
              )}
              <label>
                {tipoNuevo === "REENGANCHE"
                  ? "Nuevo monto aprobado"
                  : "Monto prestado"}
                <input
                  name="montoPrestado"
                  type="number"
                  min="1"
                  step="0.01"
                  required
                  placeholder="0.00"
                  onChange={(e) => setMontoNuevo(Number(e.target.value))}
                />
              </label>
              <label>
                Frecuencia
                <select
                  name="frecuencia"
                  required
                  value={frecuenciaNueva}
                  onChange={(e) => setFrecuenciaNueva(e.target.value)}
                >
                  <option>SEMANAL</option>
                  <option>QUINCENAL</option>
                  <option>MENSUAL</option>
                </select>
              </label>
              {tipoNuevo !== "REDITO" ? (
                <>
                  <label>
                    {frecuenciaNueva === "SEMANAL"
                      ? "Pago por semana"
                      : frecuenciaNueva === "QUINCENAL"
                        ? "Pago por quincena"
                        : "Pago por mes"}
                    <input
                      name="cuota"
                      type="number"
                      min="1"
                      step="0.01"
                      required
                      placeholder="0.00"
                      value={cuotaNueva || ""}
                      onChange={(e) => setCuotaNueva(Number(e.target.value))}
                    />
                    <small className="field-help">
                      Introduzca el pago acordado con el cliente.
                    </small>
                  </label>
                  <label>
                    {frecuenciaNueva === "SEMANAL"
                      ? "Total de semanas"
                      : frecuenciaNueva === "QUINCENAL"
                        ? "Total de quincenas"
                        : "Total de meses"}
                    <input
                      name="periodos"
                      type="number"
                      min="1"
                      step="1"
                      required
                      value={periodosNuevos}
                      onChange={(e) =>
                        setPeriodosNuevos(
                          Math.max(1, Number(e.target.value) || 1),
                        )
                      }
                    />
                    <small className="field-help">
                      13 es la base; puede escribir una cantidad mayor.
                    </small>
                  </label>
                  <div className="agreement-summary full">
                    <span>Total acordado</span>
                    <strong>{money(cuotaNueva * periodosNuevos)}</strong>
                    <small>
                      {periodosNuevos} pagos de {money(cuotaNueva)}
                    </small>
                  </div>
                </>
              ) : (
                <label className="full">
                  Rédito por período
                  <input
                    name="redito"
                    type="number"
                    min="1"
                    step="0.01"
                    required
                    placeholder="0.00"
                  />
                </label>
              )}
              <label>
                Fecha de inicio
                <input
                  name="fechaInicio"
                  type="date"
                  required
                  defaultValue={new Date().toISOString().slice(0, 10)}
                />
              </label>
              <label className="full">
                Observación
                <textarea
                  name="observacion"
                  rows={2}
                  placeholder="Información adicional (opcional)"
                />
              </label>
            </div>
            {tipoNuevo === "REENGANCHE" && (
              <p className="renewal-note">
                El saldo anterior se descontará automáticamente. El préstamo de
                origen quedará como REENGANCHADO y el nuevo comenzará ACTIVO.
              </p>
            )}
            <div className="modal-actions">
              <button
                type="button"
                className="cancel-button"
                onClick={() => setModal(false)}
              >
                Cancelar
              </button>
              <button disabled={saving}>
                {saving
                  ? "Procesando…"
                  : tipoNuevo === "REENGANCHE"
                    ? "Confirmar reenganche"
                    : "Crear préstamo"}
              </button>
            </div>
          </form>
        </div>
      )}
      {detalle && (
        <div className="drawer-backdrop" onMouseDown={() => setDetalle(null)}>
          <section
            className="loan-drawer"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="drawer-head">
              <div>
                <span>PR-{String(detalle.prestamo.id).padStart(5, "0")}</span>
                <h2>{detalle.prestamo.cliente}</h2>
              </div>
              <button className="close-button" onClick={() => setDetalle(null)}>
                ×
              </button>
            </div>
            <div className="drawer-tags">
              <span
                className={`type-badge ${detalle.prestamo.tipo === "SAN" ? "san" : "redito"}`}
              >
                {detalle.prestamo.tipo}
              </span>
              <span
                className={`loan-status ${detalle.prestamo.estado.toLowerCase()}`}
              >
                {detalle.prestamo.estado}
              </span>
            </div>
            <div className="balance-card">
              <span>Saldo pendiente</span>
              <strong>{money(detalle.prestamo.saldoPendiente)}</strong>
              <small>
                de{" "}
                {money(
                  detalle.prestamo.tipo === "SAN"
                    ? detalle.prestamo.totalPagar
                    : detalle.prestamo.montoPrestado,
                )}
              </small>
            </div>
            <dl className="loan-facts">
              <div>
                <dt>Monto prestado</dt>
                <dd>{money(detalle.prestamo.montoPrestado)}</dd>
              </div>
              <div>
                <dt>Frecuencia</dt>
                <dd>{detalle.prestamo.frecuencia}</dd>
              </div>
              <div>
                <dt>Inicio</dt>
                <dd>
                  {new Date(
                    detalle.prestamo.fechaInicio + "T00:00:00",
                  ).toLocaleDateString("es-DO")}
                </dd>
              </div>
              {detalle.prestamo.tipo === "SAN" ? (
                <>
                  <div>
                    <dt>Cuota</dt>
                    <dd>{money(detalle.prestamo.cuota)}</dd>
                  </div>
                  <div>
                    <dt>Períodos</dt>
                    <dd>{detalle.prestamo.periodos}</dd>
                  </div>
                </>
              ) : (
                <div>
                  <dt>Rédito</dt>
                  <dd>{money(detalle.prestamo.redito)}</dd>
                </div>
              )}
            </dl>
            {detalle.cuotas.length > 0 && (
              <div className="schedule">
                <h3>Plan de cuotas</h3>
                {detalle.cuotas.map((c) => (
                  <div key={c.id}>
                    <span>
                      <b>Cuota {c.numero}</b>
                      <small>
                        {new Date(
                          c.vencimiento + "T00:00:00",
                        ).toLocaleDateString("es-DO")}
                      </small>
                    </span>
                    <span>
                      <b>{money(c.programado)}</b>
                      <small>{c.estado}</small>
                    </span>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      )}
    </section>
  );
}
