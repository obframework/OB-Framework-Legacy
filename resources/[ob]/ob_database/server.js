const mysql = require('mysql2/promise');

let pool = null;
let connected = false;
let connectionError = 'A conexao com o banco ainda nao foi inicializada.';
let connectPromise = null;
let reconnectTimer = null;
let stopping = false;
let connectedBefore = false;
const subscribers = new Set();

const reconnectableCodes = new Set([
  'ECONNREFUSED',
  'ECONNRESET',
  'ETIMEDOUT',
  'EPIPE',
  'ENETUNREACH',
  'EHOSTUNREACH',
  'ENOTFOUND',
  'EAI_AGAIN',
  'PROTOCOL_CONNECTION_LOST',
  'PROTOCOL_ENQUEUE_AFTER_FATAL_ERROR',
]);

function databaseError(error) {
  return `Banco de dados indisponivel (${error?.code || 'UNKNOWN'}).`;
}

function databaseErrorDetail(error) {
  const code = error?.code || 'UNKNOWN';
  const state = error?.sqlState ? `/${error.sqlState}` : '';
  // sqlMessage identifica constraint, tabela e tipo incompatível sem expor
  // parâmetros da consulta nem a connection string.
  const message = String(error?.sqlMessage || error?.message || 'Sem detalhe adicional.')
    .replace(/[\r\n]+/g, ' ')
    .slice(0, 500);
  return `${code}${state}: ${message}`;
}

function plain(value) {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(plain);

  const result = {};
  for (const [key, entry] of Object.entries(value)) result[key] = plain(entry);
  return result;
}

function notifySubscriber(resourceName) {
  emit(`ob_database:server:ready:${resourceName}`, connected, connectionError);
}

function notifyAll() {
  for (const resourceName of subscribers) notifySubscriber(resourceName);
}

function isReconnectable(error) {
  const code = String(error?.code || '');
  return reconnectableCodes.has(code) || code.startsWith('PROTOCOL_CONNECTION_');
}

function reconnectDelay() {
  return Math.max(1000, Math.min(60000, GetConvarInt('ob_database_reconnect_ms', 5000)));
}

function clearReconnectTimer() {
  if (!reconnectTimer) return;
  clearTimeout(reconnectTimer);
  reconnectTimer = null;
}

function scheduleReconnect(error) {
  if (stopping || reconnectTimer) return;
  const delay = reconnectDelay();
  const code = error?.code || 'UNAVAILABLE';
  console.warn(`[ob_database] Banco indisponivel (${code}); nova tentativa em ${delay}ms.`);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    void connect();
  }, delay);
}

function connectionOptions(connectionString) {
  const url = new URL(connectionString);
  if (!['mysql:', 'mariadb:'].includes(url.protocol)) {
    throw new Error('INVALID_DATABASE_PROTOCOL');
  }

  const database = decodeURIComponent(url.pathname.replace(/^\//, ''));
  if (!url.hostname || !url.username || !database) {
    throw new Error('INVALID_DATABASE_CONNECTION_STRING');
  }

  return {
    host: url.hostname,
    port: Number(url.port || 3306),
    user: decodeURIComponent(url.username),
    password: decodeURIComponent(url.password),
    database,
    charset: url.searchParams.get('charset') || 'utf8mb4',
    waitForConnections: true,
    connectionLimit: Math.max(1, GetConvarInt('ob_database_pool_size', 10)),
    queueLimit: 0,
    dateStrings: true,
    supportBigNumbers: true,
    bigNumberStrings: true,
    enableKeepAlive: true,
    keepAliveInitialDelay: 0,
  };
}

async function connect() {
  if (stopping) return false;
  if (connected && pool) return true;
  if (connectPromise) return connectPromise;

  connectPromise = (async () => {
  const connectionString = GetConvar('ob_database_connection_string', '').trim();
  if (!connectionString) {
    connectionError = 'Defina ob_database_connection_string em server.private.cfg.';
    console.error(`[ob_database] ${connectionError}`);
    notifyAll();
    return false;
  }

  let candidate = null;
  try {
    candidate = mysql.createPool(connectionOptions(connectionString));
    await candidate.query('SELECT 1');
    if (stopping) {
      await candidate.end().catch(() => undefined);
      return false;
    }
    const previous = pool;
    pool = candidate;
    connected = true;
    connectionError = null;
    clearReconnectTimer();
    console.log(connectedBefore
      ? '[ob_database] Conexao MySQL/MariaDB restabelecida.'
      : '[ob_database] Conexao MySQL/MariaDB estabelecida.');
    connectedBefore = true;
    if (previous && previous !== candidate) await previous.end().catch(() => undefined);
    notifyAll();
    return true;
  } catch (error) {
    connected = false;
    connectionError = databaseError(error);
    console.error(`[ob_database] Falha de conexao: ${error?.code || 'UNKNOWN'}`);
    if (candidate) await candidate.end().catch(() => undefined);
    if (pool === candidate) pool = null;
    notifyAll();
    if (isReconnectable(error)) scheduleReconnect(error);
    return false;
  }
  })();

  try {
    return await connectPromise;
  } finally {
    connectPromise = null;
  }
}

function disconnectForRetry(error, failedPool) {
  if (!isReconnectable(error) || pool !== failedPool) return;
  connected = false;
  connectionError = databaseError(error);
  pool = null;
  notifyAll();
  scheduleReconnect(error);
  void failedPool.end().catch(() => undefined);
}

function placeholderCount(statement) {
  // As queries da base usam placeholders posicionais. A contagem antecipa o
  // erro opaco do MariaDB e nao registra nenhum valor enviado pelo jogador.
  return (statement.match(/\?/g) || []).length;
}

function resultForKind(kind, rows) {
  if (kind === 'single') return Array.isArray(rows) ? rows[0] || null : null;
  if (kind === 'scalar') {
    const row = Array.isArray(rows) ? rows[0] : null;
    return row ? Object.values(row)[0] : null;
  }
  if (kind === 'insert') return rows?.insertId ?? null;
  if (kind === 'update') return rows?.affectedRows ?? 0;
  return plain(rows);
}

function validateStatement(statement, parameters) {
  if (typeof statement !== 'string' || statement.length === 0 || statement.length > 100000) {
    throw new Error('INVALID_SQL_STATEMENT');
  }

  const values = Array.isArray(parameters) ? parameters : [];
  const expected = placeholderCount(statement);
  if (values.length !== expected) {
    const error = new Error(`PARAMETER_COUNT expected=${expected} received=${values.length}`);
    error.code = 'PARAMETER_COUNT';
    throw error;
  }
  return values;
}

async function executeTransaction(activePool, statements) {
  if (!Array.isArray(statements) || statements.length === 0 || statements.length > 100) {
    throw new Error('INVALID_TRANSACTION');
  }

  const connection = await activePool.getConnection();
  try {
    await connection.beginTransaction();
    const results = [];
    for (const entry of statements) {
      if (!entry || typeof entry !== 'object') throw new Error('INVALID_TRANSACTION_ENTRY');
      const entryKind = typeof entry.kind === 'string' ? entry.kind : 'query';
      const values = validateStatement(entry.statement, entry.parameters);
      const [rows] = await connection.execute(entry.statement, values);
      if (Number.isFinite(entry.expectAffectedMin)
          && Number(rows?.affectedRows || 0) < Number(entry.expectAffectedMin)) {
        const error = new Error('EXPECTED_AFFECTED_ROWS');
        error.code = 'EXPECTED_AFFECTED_ROWS';
        throw error;
      }
      results.push(resultForKind(entryKind, rows));
    }
    await connection.commit();
    return plain(results);
  } catch (error) {
    await connection.rollback().catch(() => undefined);
    throw error;
  } finally {
    connection.release();
  }
}

async function execute(activePool, kind, statement, parameters) {
  if (kind === 'transaction') return executeTransaction(activePool, statement);
  const values = validateStatement(statement, parameters);
  const [rows] = await activePool.execute(statement, values);
  return resultForKind(kind, rows);
}

on('ob_database:server:subscribe', (resourceName) => {
  if (typeof resourceName !== 'string' || resourceName.length === 0) return;
  subscribers.add(resourceName);
  notifySubscriber(resourceName);
});

on('ob_database:server:request', async (resourceName, requestId, kind, statement, parameters) => {
  if (!subscribers.has(resourceName) || typeof requestId !== 'string') return;

  if (!connected || !pool) {
    emit(`ob_database:server:response:${resourceName}`, requestId, false, null, connectionError);
    return;
  }

  const activePool = pool;
  try {
    const result = await execute(activePool, kind, statement, parameters);
    emit(`ob_database:server:response:${resourceName}`, requestId, true, result, null);
  } catch (error) {
    const preview = kind === 'transaction'
      ? `[transaction:${Array.isArray(statement) ? statement.length : 0}]`
      : String(statement).replace(/\s+/g, ' ').slice(0, 180);
    const received = Array.isArray(parameters) ? parameters.length : 0;
    console.error(`[ob_database] Consulta falhou em ${resourceName} (${kind}; params=${received}; sql="${preview}"): ${databaseErrorDetail(error)}`);
    disconnectForRetry(error, activePool);
    emit(`ob_database:server:response:${resourceName}`, requestId, false, null, databaseError(error));
  }
});

on('onResourceStart', (resourceName) => {
  if (resourceName === GetCurrentResourceName()) void connect();
});

on('onResourceStop', async (resourceName) => {
  if (resourceName !== GetCurrentResourceName()) {
    subscribers.delete(resourceName);
    return;
  }

  stopping = true;
  clearReconnectTimer();
  connected = false;
  const activePool = pool;
  pool = null;
  if (activePool) await activePool.end().catch(() => undefined);
});
