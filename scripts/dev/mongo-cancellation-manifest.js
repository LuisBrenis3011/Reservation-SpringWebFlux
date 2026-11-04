// Solo lectura. Canal Base64 para no depender del quoting de argumentos en PowerShell 5.1.
const input = process.env.EATS_CANCELLATION_EXPECTATIONS_BASE64;
if (!input || !/^[A-Za-z0-9+/]+={0,2}$/.test(input)) throw new Error('Expectativas Base64 ausentes o invalidas');
let expected;
try { expected = JSON.parse(Buffer.from(input, 'base64').toString('utf8')); }
catch (_) { throw new Error('Expectativas JSON invalidas'); }
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
if (!uuidPattern.test(expected.restaurantId) || !uuidPattern.test(expected.reservationId) ||
    typeof expected.issuer !== 'string' || typeof expected.subject !== 'string' || typeof expected.key !== 'string' ||
    typeof expected.match !== 'string')
    throw new Error('Expectativas incompletas');
const name = process.env.EATS_BACKUP_DATABASE;
if (!name || !/^[A-Za-z0-9_-]{1,63}$/.test(name) || ['admin','local','config'].includes(name)) throw new Error('Base no permitida');
if (!db.getSiblingDB('admin').auth(process.env.MONGO_INITDB_ROOT_USERNAME, process.env.MONGO_INITDB_ROOT_PASSWORD)) throw new Error('Autenticacion fallida');
const hello = db.adminCommand({hello:1});
if (hello.setName !== 'rs0' || !hello.isWritablePrimary) throw new Error('Se requiere rs0 PRIMARY');
const crypto = require('crypto');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const canonical = value => EJSON.stringify(value,null,0,{relaxed:false});
const owner = canonical(UUID(expected.restaurantId));
const id = canonical(UUID(expected.reservationId));
const receiptKey = 'rsv:' + hash(JSON.stringify([expected.issuer,expected.subject,expected.key]));
const fingerprint=hash(JSON.stringify([expected.issuer,expected.subject,'POST',`/restaurants/${expected.restaurantId}/reservations/${expected.reservationId}/cancellation`,'',expected.match]));
const target = db.getSiblingDB(name);
function uuidText(value) {
    if (typeof value === 'string' && uuidPattern.test(value)) return value;
    const binary=EJSON.serialize(value,{relaxed:false})?.$binary;
    if (!binary || binary.subType !== '04') throw new Error('UUID no verificable');
    const hex=Buffer.from(binary.base64,'base64').toString('hex');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
const timestamp=value=>value instanceof Date?value.toISOString():value;
function view(row, storedReservation) {
    return {kind:'MANAGED',id:uuidText(storedReservation?row._id:(row.id??row._id)),restaurantId:uuidText(row.restaurantId),
        owner:storedReservation?{issuer:row.customerIssuer,subject:row.customerSubject}:{issuer:row.owner.issuer,subject:row.owner.subject},
        shiftId:uuidText(row.shiftId),partySize:Number(row.partySize),notes:row.notes,status:row.status,version:Number(row.version),
        tableIds:row.tableIds.map(uuidText),combinationId:row.combinationId?uuidText(row.combinationId):null,assignedCapacity:Number(row.assignedCapacity),
        localStart:row.localStart,localEnd:row.localEnd,zoneId:row.zoneId,startInstant:timestamp(row.startInstant),endInstant:timestamp(row.endInstant),
        createdAt:timestamp(row.createdAt),updatedAt:timestamp(row.updatedAt),cancelledAt:row.cancelledAt?timestamp(row.cancelledAt):null};
}
const protectedCollections=[];
let reservation=null, operation=null, receipt=null, receiptCount=0;
for (const info of target.getCollectionInfos().sort((a,b)=>a.name.localeCompare(b.name))) {
    if (info.type !== 'collection' || info.options?.timeseries || info.name.startsWith('system.')) throw new Error('Coleccion no admitida');
    const rows=[];
    target.getCollection(info.name).find({}).sort({_id:1}).forEach(row=>{
        if (info.name === 'reservations' && canonical(row._id) === id) { reservation=row; return; }
        if (info.name === 'restaurant_operations' && canonical(row._id) === owner) { operation=row; return; }
        if (info.name === 'operation_receipts' && canonical(row.restaurantId) === owner && row.idempotencyKey === receiptKey) {
            receipt=row; receiptCount++; return;
        }
        rows.push(canonical(row));
    });
    const indexes=target.getCollection(info.name).getIndexes().sort((a,b)=>a.name.localeCompare(b.name)).map(index=>{
        delete index.ns; const normalized={}; for (const key of Object.keys(index).sort()) normalized[key]=index[key]; return canonical(normalized);
    });
    protectedCollections.push({name:info.name,count:rows.length,documentsSha256:hash(rows.join('\n')),indexesSha256:hash(indexes.join('\n')),options:canonical(info.options)});
}
if (!reservation || !operation) throw new Error('Reserva o revision ausentes');
const invariant={...reservation};
for (const key of ['status','version','updatedAt','cancelledAt']) delete invariant[key];
const operationInvariant={...operation}; delete operationInvariant.revision;
print(JSON.stringify({protectedCollections,reservationInvariantSha256:hash(canonical(invariant)),operationInvariantSha256:hash(canonical(operationInvariant)),
    reservationSha256:hash(canonical(reservation)),version:Number(reservation.version),revision:Number(operation.revision),receiptCount,
    receiptSha256:receipt?hash(canonical(receipt)):null,
    receiptVersion:receipt?Number(receipt.responseBody?.version):null,
    receiptRevision:receipt?Number(receipt.resultingRevision):null,
    receiptStatus:receipt?receipt.httpStatus:null,receiptLocation:receipt?(receipt.location??null):null,
    receiptFingerprintMatches:receipt?receipt.fingerprint===fingerprint:null,
    reservationView:view(reservation,true),receiptView:receipt?view(receipt.responseBody,false):null,
    tableSnapshots:reservation.tableSnapshots.map(t=>({id:uuidText(t.id??t._id),capacity:Number(t.capacity)}))}));
