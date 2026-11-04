// Solo lectura en origen y destino; no imprime claves de idempotencia ni cuerpos.
function decodeShiftExpectations(encoded) {
    if (typeof encoded !== 'string' || !encoded.length) {
        throw new Error('Faltan expectativas Base64 de SPEC-003');
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
        throw new Error('Expectativas Base64/UTF-8/JSON de SPEC-003 invalidas; no se imprime su contenido');
    }
}
const expected = decodeShiftExpectations(process.env.EATS_SHIFT_EXPECTATIONS_BASE64);
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
    !Number.isSafeInteger(expected.revision) || !expected.zone || !Array.isArray(expected.shifts) || expected.shifts.length !== 2 ||
    !Array.isArray(expected.receipts) || expected.receipts.length !== 7) throw new Error('Expectativas de SPEC-003 incompletas');
const target = db.getSiblingDB(name);
const owner = UUID(expected.restaurantId);
const canonical = value => EJSON.stringify(value, null, 0, {relaxed: false});
const sameUuid = (value, text) => canonical(value) === canonical(UUID(text));
for (const collection of ['restaurants','restaurant_operations','restaurant_time_zones','restaurant_shifts','operation_receipts']) {
    if (!target.getCollectionNames().includes(collection)) throw new Error('Falta coleccion de SPEC-003');
}
const restaurant = target.restaurants.findOne({_id:owner});
if (!restaurant || restaurant.localIdentityFixture !== 'eats-hub-local/v1') throw new Error('Restaurante ajeno');
const operation = target.restaurant_operations.findOne({_id:owner});
if (!operation || Number(operation.revision) !== expected.revision) throw new Error('Revision distinta');
const zone = target.restaurant_time_zones.findOne({_id:owner});
if (!zone || zone.zoneId !== expected.zone.zoneId || expected.zone.restaurantId !== expected.restaurantId || expected.zone.revision !== expected.revision) throw new Error('Zona distinta');
const zoneIndex = target.restaurant_time_zones.getIndexes().find(i => i.name === '_id_');
const shiftIndex = target.restaurant_shifts.getIndexes().find(i => i.name === 'restaurant_shift_interval');
if (!zoneIndex || Object.keys(zoneIndex.key).join(',') !== '_id' || zoneIndex.key._id !== 1 ||
    !shiftIndex || shiftIndex.unique || shiftIndex.sparse || shiftIndex.partialFilterExpression ||
    Object.keys(shiftIndex.key).join(',') !== 'restaurantId,startInstant,endInstant' ||
    shiftIndex.key.restaurantId !== 1 || shiftIndex.key.startInstant !== 1 || shiftIndex.key.endInstant !== 1) throw new Error('Indices temporales distintos');
const instantEqual = (actual, text) => {
    const a = new Date(actual).getTime(), b = new Date(text).getTime();
    return Number.isFinite(a) && Number.isFinite(b) && a === b;
};
function checkShift(actual, row, receipt) {
    if (!actual || !sameUuid(actual.id || actual._id, row.id) || !sameUuid(actual.restaurantId, expected.restaurantId) ||
        actual.localStart !== row.localStart || actual.localEnd !== row.localEnd || actual.zoneId !== row.zoneId ||
        !instantEqual(actual.startInstant,row.startInstant) || !instantEqual(actual.endInstant,row.endInstant) ||
        (receipt && Number(actual.revision) !== row.revision)) throw new Error('Turno o snapshot temporal distintos');
}
if (target.restaurant_shifts.countDocuments({restaurantId:owner}) !== 2) throw new Error('Conjunto de turnos distinto');
const ids = new Set();
for (const row of expected.shifts) {
    if (ids.has(row.id) || row.revision !== expected.revision || row.restaurantId !== expected.restaurantId) throw new Error('Turnos esperados invalidos');
    ids.add(row.id);
    checkShift(target.restaurant_shifts.findOne({_id:UUID(row.id),restaurantId:owner}),row,false);
}
const keys = new Set();
for (const receipt of expected.receipts) {
    if (typeof receipt.key !== 'string' || !receipt.key || keys.has(receipt.key)) throw new Error('Recibos esperados invalidos');
    keys.add(receipt.key);
    const rows = target.operation_receipts.find({restaurantId:owner,idempotencyKey:receipt.key}).toArray();
    if (rows.length !== 1) throw new Error('Recibo ausente o duplicado');
    const stored = rows[0], body = stored.responseBody;
    if (!body || Number(stored.httpStatus) !== receipt.status || Number(stored.resultingRevision) !== receipt.body.revision ||
        Number(body.revision) !== receipt.body.revision || (stored.location || '') !== (receipt.location || '') ||
        !/^[a-f0-9]{64}$/.test(stored.fingerprint)) throw new Error('Metadatos del recibo distintos');
    if (receipt.body.id) checkShift(body,receipt.body,true);
    else if (!sameUuid(body.restaurantId,expected.restaurantId) || body.zoneId !== receipt.body.zoneId) throw new Error('Recibo de zona distinto');
}
print(JSON.stringify({spec:'SPEC-003',revision:expected.revision,zoneId:zone.zoneId,shifts:ids.size,
    acceptedReceipts:keys.size,zoneIndex:zoneIndex.name,shiftIndex:shiftIndex.name}));