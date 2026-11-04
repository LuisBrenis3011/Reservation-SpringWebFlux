// Solo lectura en origen y destino; no imprime claves de idempotencia ni cuerpos.
function decodeCombinationExpectations(encoded) {
    if (typeof encoded !== 'string' || !encoded.length) {
        throw new Error('Faltan expectativas Base64 de SPEC-002');
    }
    try {
        if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) throw new Error();
        const bytes = Buffer.from(encoded, 'base64');
        const json = bytes.toString('utf8');
        if (bytes.toString('base64') !== encoded || !Buffer.from(json, 'utf8').equals(bytes)) throw new Error();
        const value = JSON.parse(json);
        if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
        return value;
    } catch (_) {
        throw new Error('Expectativas Base64/UTF-8/JSON de SPEC-002 invalidas; no se imprime su contenido');
    }
}
const expected = decodeCombinationExpectations(process.env.EATS_COMBINATION_EXPECTATIONS_BASE64);
const name = process.env.EATS_BACKUP_DATABASE;
if (!name || !/^[A-Za-z0-9_-]{1,63}$/.test(name) || ['admin', 'local', 'config'].includes(name)) {
    throw new Error('Base no permitida');
}
if (process.env.EATS_BACKUP_SOURCE === 'true') {
    if (!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,
        process.env.MONGO_INITDB_ROOT_PASSWORD)) throw new Error('Autenticacion fallida');
    const hello = db.adminCommand({hello: 1});
    if (hello.setName !== 'rs0' || !hello.isWritablePrimary) throw new Error('Origen requiere rs0 PRIMARY');
}
if (expected.restaurantId !== '11111111-1111-4111-8111-111111111111' ||
    !Number.isSafeInteger(expected.revision) || !Array.isArray(expected.receipts) || expected.receipts.length !== 7 ||
    !Array.isArray(expected.combinations) || expected.combinations.length < 2 || !Array.isArray(expected.tables)) {
    throw new Error('Expectativas de SPEC-002 incompletas');
}
const target = db.getSiblingDB(name);
const owner = UUID(expected.restaurantId);
const canonical = value => EJSON.stringify(value, null, 0, {relaxed: false});
const sameUuid = (value, text) => canonical(value) === canonical(UUID(text));
const required = ['restaurants', 'restaurant_tables', 'table_combinations', 'restaurant_operations', 'operation_receipts'];
const names = target.getCollectionNames();
for (const collection of required) {
    if (!names.includes(collection)) throw new Error('Falta una coleccion requerida para SPEC-002');
}
const restaurant = target.restaurants.findOne({_id: owner});
if (!restaurant || restaurant.localIdentityFixture !== 'eats-hub-local/v1') throw new Error('Restaurante de ensayo inesperado');
const operation = target.restaurant_operations.findOne({_id: owner});
if (!operation || Number(operation.revision) !== expected.revision) throw new Error('Revision distinta del checkpoint');
const unique = target.table_combinations.getIndexes().find(index => index.name === 'restaurant_combination_members_unique');
if (!unique || unique.unique !== true || unique.sparse || unique.partialFilterExpression ||
    Object.keys(unique.key).join(',') !== 'restaurantId,memberKey' || unique.key.restaurantId !== 1 || unique.key.memberKey !== 1) {
    throw new Error('Falta el indice unico completo de combinaciones');
}
if (target.restaurant_tables.countDocuments({restaurantId: owner}) !== expected.tables.length ||
    target.table_combinations.countDocuments({restaurantId: owner}) !== expected.combinations.length) {
    throw new Error('Cambian los conjuntos de mesas o combinaciones del checkpoint');
}
for (const row of expected.tables) {
    const stored = target.restaurant_tables.findOne({_id: UUID(row.id), restaurantId: owner});
    if (!stored || stored.label !== row.label || Number(stored.capacity) !== row.capacity) throw new Error('Mesa del checkpoint distinta');
}
for (const row of expected.combinations) {
    const stored = target.table_combinations.findOne({_id: UUID(row.id), restaurantId: owner});
    const ids = row.tableIds.slice().sort();
    if (!stored || !Array.isArray(stored.tableIds) || stored.tableIds.length !== ids.length ||
        stored.tableIds.some((id, i) => !sameUuid(id, ids[i])) || stored.memberKey !== ids.join(',')) {
        throw new Error('Identidad o integrantes de combinacion distintos');
    }
    let capacity = 0;
    for (const id of ids) {
        const table = target.restaurant_tables.findOne({_id: UUID(id), restaurantId: owner});
        if (!table) throw new Error('Integrante inexistente');
        capacity += Number(table.capacity);
    }
    if (capacity !== row.capacity) throw new Error('Capacidad derivada distinta');
}
const keys = new Set();
for (const receipt of expected.receipts) {
    if (typeof receipt.key !== 'string' || !receipt.key || keys.has(receipt.key)) throw new Error('Claves de recibo invalidas');
    keys.add(receipt.key);
    const rows = target.operation_receipts.find({restaurantId: owner, idempotencyKey: receipt.key}).toArray();
    if (rows.length !== 1) throw new Error('No existe un unico recibo por comando');
    const stored = rows[0];
    const body = stored.responseBody;
    if (!body || Number(stored.httpStatus) !== receipt.status || Number(stored.resultingRevision) !== receipt.body.revision ||
        (stored.location || '') !== (receipt.location || '') || !/^[a-f0-9]{64}$/.test(stored.fingerprint) ||
        !sameUuid(body.id || body._id, receipt.body.id) || !sameUuid(body.restaurantId, expected.restaurantId) ||
        Number(body.revision) !== receipt.body.revision || Number(body.capacity) !== receipt.body.capacity) {
        throw new Error('Recibo original o respuesta historica distintos');
    }
    if (Array.isArray(receipt.body.tableIds)) {
        if (!Array.isArray(body.tableIds) || body.tableIds.length !== receipt.body.tableIds.length ||
            body.tableIds.some((id, i) => !sameUuid(id, receipt.body.tableIds[i]))) throw new Error('Integrantes historicos distintos');
    } else if (body.label !== receipt.body.label) throw new Error('Etiqueta historica distinta');
}
print(JSON.stringify({spec: 'SPEC-002', revision: expected.revision, tables: expected.tables.length,
    combinations: expected.combinations.length, acceptedReceipts: keys.size, uniqueIndex: unique.name}));
