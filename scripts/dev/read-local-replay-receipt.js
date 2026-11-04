// Lectura restringida al alta de la mesa de evidencia; la salida se consume en
// memoria por PowerShell. Nunca guardar/imprimir esta salida manualmente.
const databaseName = process.env.EATS_BACKUP_DATABASE;
const tableId = process.env.EATS_REPLAY_TABLE;
const owner = '11111111-1111-4111-8111-111111111111';
if (!databaseName || !/^[A-Za-z0-9_-]{1,63}$/.test(databaseName) ||
    ['admin', 'local', 'config'].includes(databaseName)) throw new Error('Base no permitida');
if (!/^[0-9a-f-]{36}$/.test(tableId || '')) throw new Error('Mesa de evidencia invalida');
if (!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME,
    process.env.MONGO_INITDB_ROOT_PASSWORD)) throw new Error('Autenticacion fallida');
const hello = db.adminCommand({hello: 1});
if (hello.setName !== 'rs0' || !hello.isWritablePrimary) throw new Error('Origen inesperado');
const target = db.getSiblingDB(databaseName);
const fixture = target.restaurants.findOne({_id: UUID(owner)});
if (!fixture || fixture.localIdentityFixture !== 'eats-hub-local/v1') throw new Error('No es el restaurante de pruebas');
const receipts = target.operation_receipts.find({restaurantId: UUID(owner), httpStatus: 201,
    $or: [{'responseBody._id': UUID(tableId)}, {'responseBody.id': UUID(tableId)}]}).toArray();
if (receipts.length !== 1) throw new Error('No existe un unico recibo de alta; no se enviara POST');
const receipt = receipts[0];
const body = receipt.responseBody;
const capacity = Number(body.capacity);
if (typeof body.label !== 'string' || !body.label.startsWith('Mesa validacion ') ||
    capacity !== 4) throw new Error('No corresponde al alta del script de verificacion');
const path = '/restaurants/' + owner + '/tables';
const requestBody = JSON.stringify({label: body.label, capacity});
const fingerprint = require('crypto').createHash('sha256')
    .update('POST\n' + path + '\n' + requestBody + '\nnull').digest('hex');
if (fingerprint !== receipt.fingerprint || typeof receipt.idempotencyKey !== 'string') {
    throw new Error('No se puede reconstruir exactamente el comando original; no se enviara POST');
}
const expectedLocation = '/catalog' + path + '/' + tableId;
if (receipt.location !== expectedLocation) throw new Error('Location del recibo inesperada');
print(JSON.stringify({key: receipt.idempotencyKey, requestBody, location: receipt.location,
    expected: {id: tableId, restaurantId: owner, label: body.label, capacity,
        revision: Number(receipt.resultingRevision)}}));
